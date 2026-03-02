require "test_helper"

class RailsInformant::Notifiers::WebhookTest < ActiveSupport::TestCase
  include StubHTTPHelpers

  setup do
    @notifier = RailsInformant::Notifiers::Webhook.new
    RailsInformant.config.webhook_url = "https://example.com/webhook"
  end

  test "notify sends HTTP POST with JSON payload" do
    group = create_error_group
    occurrence = group.occurrences.create!(
      backtrace: [ "/app/foo.rb:1" ],
      git_sha: "abc123"
    )

    stub_http = stub_http_api

    @notifier.notify(group, occurrence)

    payload = JSON.parse(stub_http.captured_request.body)
    assert_equal "StandardError", payload["error_class"]
    assert_equal group.fingerprint, payload["fingerprint"]
    assert_nil payload["occurrence"]
  end

  test "excludes PII from payload" do
    group = create_error_group
    occurrence = group.occurrences.create!(
      backtrace: [ "/app/foo.rb:1" ],
      user_context: { "id" => 42, "email" => "test@example.com" }
    )

    stub_http = stub_http_api

    @notifier.notify(group, occurrence)

    payload = JSON.parse(stub_http.captured_request.body)
    assert_nil payload["user_context"]
    assert_nil payload["occurrence"]
  end

  test "sets SNI hostname for TLS verification against the original hostname" do
    group = create_error_group
    occurrence = group.occurrences.create!(backtrace: [ "/app/foo.rb:1" ])

    stub_http = stub_http_api

    @notifier.notify(group, occurrence)

    assert_equal true, stub_http.verify_hostname
    assert_equal "example.com", stub_http.hostname
  end

  test "raises on non-HTTPS URL" do
    RailsInformant.config.webhook_url = "http://example.com/webhook"
    group = create_error_group
    occurrence = group.occurrences.create!(backtrace: [ "/app/foo.rb:1" ])

    assert_raises(ArgumentError) { @notifier.notify(group, occurrence) }
  end

  test "raises on non-success response" do
    group = create_error_group
    occurrence = group.occurrences.create!(backtrace: [ "/app/foo.rb:1" ])

    stub_http_api response_class: Net::HTTPInternalServerError, code: "500", body: "Server error"

    error = assert_raises(RailsInformant::NotifierError) { @notifier.notify(group, occurrence) }
    assert_includes error.message, "Webhook error: HTTP 500"
  end
end
