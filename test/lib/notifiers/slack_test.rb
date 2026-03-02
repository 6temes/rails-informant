require "test_helper"

class RailsInformant::Notifiers::SlackTest < ActiveSupport::TestCase
  setup do
    @notifier = RailsInformant::Notifiers::Slack.new
    RailsInformant.config.slack_webhook_url = "https://hooks.slack.com/test"
  end

  test "should_notify? returns true for first occurrence" do
    group = build_group(total_occurrences: 1)
    assert @notifier.should_notify?(group)
  end

  test "should_notify? returns true at milestone counts" do
    [ 10, 100, 1000 ].each do |count|
      group = build_group(total_occurrences: count, last_notified_at: Time.current)
      assert @notifier.should_notify?(group), "Expected true at count #{count}"
    end
  end

  test "should_notify? returns true when never notified" do
    group = build_group(total_occurrences: 5, last_notified_at: nil)
    assert @notifier.should_notify?(group)
  end

  test "should_notify? returns true after cooldown" do
    group = build_group(
      total_occurrences: 5,
      last_notified_at: 2.hours.ago
    )
    assert @notifier.should_notify?(group)
  end

  test "should_notify? returns false within cooldown" do
    group = build_group(
      total_occurrences: 5,
      last_notified_at: 30.minutes.ago
    )
    assert_not @notifier.should_notify?(group)
  end

  test "notify sends HTTP POST" do
    group = create_group
    occurrence = group.occurrences.create!(
      backtrace: [ "/app/foo.rb:1" ],
      git_sha: "abc123"
    )

    mock_response = Net::HTTPOK.new("1.1", "200", "OK")
    Net::HTTP.expects(:post).returns(mock_response)

    @notifier.notify(group, occurrence)
  end

  test "payload includes Block Kit structure" do
    group = create_group
    occurrence = group.occurrences.create!(backtrace: [ "/app/foo.rb:1" ])

    payload = nil
    Net::HTTP.stubs(:post).with { |_, body, _| payload = JSON.parse(body); true }

    @notifier.notify(group, occurrence)

    assert payload["blocks"].is_a?(Array)
    assert_equal "header", payload["blocks"].first["type"]
  end

  private

  def build_group(total_occurrences: 1, last_notified_at: nil, status: "unresolved")
    RailsInformant::ErrorGroup.new(
      fingerprint: SecureRandom.hex(8),
      error_class: "StandardError",
      message: "test error",
      status: status,
      total_occurrences: total_occurrences,
      last_notified_at: last_notified_at,
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )
  end

  def create_group
    RailsInformant::ErrorGroup.create!(
      fingerprint: SecureRandom.hex(8),
      error_class: "StandardError",
      message: "test error",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )
  end
end
