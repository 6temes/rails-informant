require "test_helper"
require "net/http"

class RailsInformant::NotifyJobTest < ActiveSupport::TestCase
  setup do
    RailsInformant.config.slack_webhook_url = "https://hooks.slack.com/test"
  end

  test "notifies when should_notify? returns true" do
    group = create_group_with_occurrence

    Net::HTTP.expects(:post).once.returns(Net::HTTPOK.new("1.1", "200", "OK"))

    RailsInformant::NotifyJob.perform_now(group.id)
  end

  test "skips notification when group not found" do
    Net::HTTP.expects(:post).never
    RailsInformant::NotifyJob.perform_now(-1)
  end

  test "updates last_notified_at after notification" do
    group = create_group_with_occurrence

    Net::HTTP.stubs(:post).returns(Net::HTTPOK.new("1.1", "200", "OK"))

    assert_nil group.last_notified_at
    RailsInformant::NotifyJob.perform_now(group.id)
    group.reload
    assert_not_nil group.last_notified_at
  end

  test "network errors propagate for retry_on" do
    group = create_group_with_occurrence

    Net::HTTP.stubs(:post).raises(SocketError, "connection refused")

    assert_raises SocketError do
      RailsInformant::NotifyJob.new.perform(group.id)
    end
  end

  test "continues to second notifier when first fails" do
    RailsInformant.config.webhook_url = "https://example.com/webhook"
    group = create_group_with_occurrence

    slack_stub = Net::HTTP.stubs(:post).with { |uri, *| uri.host == "hooks.slack.com" }
    slack_stub.raises(SocketError, "slack down")

    webhook_stub = Net::HTTP.stubs(:post).with { |uri, *| uri.host == "example.com" }
    webhook_stub.returns(Net::HTTPOK.new("1.1", "200", "OK"))

    assert_raises SocketError do
      RailsInformant::NotifyJob.new.perform(group.id)
    end

    group.reload
    assert_not_nil group.last_notified_at
  end

  test "does not notify when no webhook configured" do
    RailsInformant.config.slack_webhook_url = nil
    group = create_group_with_occurrence

    Net::HTTP.expects(:post).never
    RailsInformant::NotifyJob.perform_now(group.id)
  end

  private

  def create_group_with_occurrence
    group = RailsInformant::ErrorGroup.create!(
      fingerprint: SecureRandom.hex(8),
      error_class: "StandardError",
      message: "test",
      total_occurrences: 1,
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )
    group.occurrences.create!(backtrace: [ "/app/foo.rb:1" ])
    group
  end
end
