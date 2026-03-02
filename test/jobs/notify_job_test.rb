require "test_helper"
require "net/http"

class RailsInformant::NotifyJobTest < ActiveSupport::TestCase
  include StubHTTPHelpers

  setup do
    RailsInformant.config.slack_webhook_url = "https://hooks.slack.com/test"
  end

  test "notifies when should_notify? returns true" do
    group = create_error_group_with_occurrence

    stub_http_api

    assert_nothing_raised { RailsInformant::NotifyJob.perform_now(group) }
  end

  test "updates last_notified_at after notification" do
    group = create_error_group_with_occurrence

    stub_http_api

    assert_nil group.last_notified_at
    RailsInformant::NotifyJob.perform_now(group)
    group.reload
    assert_not_nil group.last_notified_at
  end

  test "does not update last_notified_at when notifier fails" do
    group = create_error_group_with_occurrence

    stub_http_failure

    assert_nil group.last_notified_at
    assert_raises(SocketError) do
      RailsInformant::NotifyJob.new.perform(group)
    end
    group.reload
    assert_nil group.last_notified_at
  end

  test "network errors propagate for retry_on" do
    group = create_error_group_with_occurrence

    stub_http_failure

    assert_raises SocketError do
      RailsInformant::NotifyJob.new.perform(group)
    end
  end

  test "continues to second notifier when first fails" do
    RailsInformant.config.webhook_url = "https://example.com/webhook"
    group = create_error_group_with_occurrence

    # Stub at notifier level: first notifier (Slack) raises, second (Webhook) succeeds
    slack_notifier = RailsInformant.config.notifiers.find { it.is_a?(RailsInformant::Notifiers::Slack) }
    slack_notifier.stubs(:notify).raises(SocketError, "slack down")

    stub_http_api

    assert_raises SocketError do
      RailsInformant::NotifyJob.new.perform(group)
    end

    group.reload
    assert_nil group.last_notified_at
  end

  test "does not notify when no webhook configured" do
    RailsInformant.config.slack_webhook_url = nil
    group = create_error_group_with_occurrence

    Net::HTTP.expects(:start).never
    RailsInformant::NotifyJob.perform_now(group)
  end
end
