require "test_helper"

class RailsInformant::Notifiers::SlackTest < ActiveSupport::TestCase
  include StubHTTPHelpers

  setup do
    @notifier = RailsInformant::Notifiers::Slack.new
    RailsInformant.config.slack_webhook_url = "https://hooks.slack.com/test"
  end

  test "should_notify? returns true for first occurrence" do
    group = build_error_group(total_occurrences: 1)
    assert @notifier.should_notify?(group)
  end

  test "should_notify? returns true at milestone counts" do
    [ 10, 100, 1000 ].each do |count|
      group = build_error_group(total_occurrences: count, last_notified_at: Time.current)
      assert @notifier.should_notify?(group), "Expected true at count #{count}"
    end
  end

  test "should_notify? returns true when never notified" do
    group = build_error_group(total_occurrences: 5, last_notified_at: nil)
    assert @notifier.should_notify?(group)
  end

  test "should_notify? returns true after cooldown" do
    group = build_error_group(
      total_occurrences: 5,
      last_notified_at: 2.hours.ago
    )
    assert @notifier.should_notify?(group)
  end

  test "should_notify? returns false within cooldown" do
    group = build_error_group(
      total_occurrences: 5,
      last_notified_at: 30.minutes.ago
    )
    assert_not @notifier.should_notify?(group)
  end

  test "notify sends HTTP POST" do
    group = create_error_group
    occurrence = group.occurrences.create!(
      backtrace: [ "/app/foo.rb:1" ],
      git_sha: "abc123"
    )

    stub_http_api

    assert_nothing_raised { @notifier.notify(group, occurrence) }
  end

  test "payload includes Block Kit structure" do
    group = create_error_group
    occurrence = group.occurrences.create!(backtrace: [ "/app/foo.rb:1" ])

    stub_http = stub_http_api

    @notifier.notify(group, occurrence)

    payload = JSON.parse(stub_http.captured_request.body)
    assert payload["blocks"].is_a?(Array)
    assert_equal "header", payload["blocks"].first["type"]
  end

  test "raises on non-HTTPS URL" do
    RailsInformant.config.slack_webhook_url = "http://hooks.slack.com/test"
    group = create_error_group
    occurrence = group.occurrences.create!(backtrace: [ "/app/foo.rb:1" ])

    assert_raises(ArgumentError) { @notifier.notify(group, occurrence) }
  end

  test "raises on non-success response" do
    group = create_error_group
    occurrence = group.occurrences.create!(backtrace: [ "/app/foo.rb:1" ])

    stub_http_api response_class: Net::HTTPInternalServerError, code: "500", body: "Server error"

    error = assert_raises(RailsInformant::NotifierError) { @notifier.notify(group, occurrence) }
    assert_includes error.message, "Slack webhook error: HTTP 500"
  end

  test "uses String#truncate instead of custom truncate" do
    assert_not RailsInformant::Notifiers::Slack.private_method_defined?(:truncate)
  end

  test "payload includes REGRESSION tag when previously resolved error reoccurs" do
    group = create_error_group(status: "unresolved")
    group.update_columns fix_deployed_at: 1.day.ago
    occurrence = group.occurrences.create!(backtrace: [ "/app/foo.rb:1" ])

    stub_http = stub_http_api

    @notifier.notify(group, occurrence)

    payload = JSON.parse(stub_http.captured_request.body)
    header_text = payload["blocks"].first.dig("text", "text")
    assert_includes header_text, "[REGRESSION]"
  end

  test "payload omits REGRESSION tag for normal errors" do
    group = create_error_group
    occurrence = group.occurrences.create!(backtrace: [ "/app/foo.rb:1" ])

    stub_http = stub_http_api

    @notifier.notify(group, occurrence)

    payload = JSON.parse(stub_http.captured_request.body)
    header_text = payload["blocks"].first.dig("text", "text")
    assert_not_includes header_text, "REGRESSION"
  end

  test "payload includes location field with controller_action" do
    group = create_error_group(controller_action: "users#show")
    occurrence = group.occurrences.create!(backtrace: [ "/app/foo.rb:1" ])

    stub_http = stub_http_api

    @notifier.notify(group, occurrence)

    payload = JSON.parse(stub_http.captured_request.body)
    fields = payload["blocks"][2]["fields"]
    location = fields.find { it["text"].include?("Location") }
    assert_includes location["text"], "users#show"
  end

  test "payload includes context block with git sha" do
    group = create_error_group
    occurrence = group.occurrences.create!(
      backtrace: [ "/app/foo.rb:1" ],
      git_sha: "abc1234def5678"
    )

    stub_http = stub_http_api

    @notifier.notify(group, occurrence)

    payload = JSON.parse(stub_http.captured_request.body)
    context_block = payload["blocks"].find { it["type"] == "context" }
    assert_not_nil context_block
    deploy_element = context_block["elements"].find { it["text"].include?("Deploy") }
    assert_includes deploy_element["text"], "abc1234"
  end
end
