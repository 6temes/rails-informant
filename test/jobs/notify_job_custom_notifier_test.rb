require "test_helper"
require "net/http"

class RailsInformant::NotifyJobCustomNotifierTest < ActiveSupport::TestCase
  include StubHTTPHelpers

  test "custom notifier registered via add_notifier is called" do
    RailsInformant.config.slack_webhook_url = nil
    group = create_error_group_with_occurrence

    custom = mock("custom_notifier")
    custom.expects(:should_notify?).with(group).returns(true)
    custom.expects(:notify).with(group, group.occurrences.last)

    RailsInformant.config.add_notifier custom

    RailsInformant::NotifyJob.perform_now(group)
  end

  test "custom notifier skipped when should_notify? returns false" do
    RailsInformant.config.slack_webhook_url = nil
    group = create_error_group_with_occurrence

    custom = mock("custom_notifier")
    custom.expects(:should_notify?).with(group).returns(false)
    custom.expects(:notify).never

    RailsInformant.config.add_notifier custom

    RailsInformant::NotifyJob.perform_now(group)
  end

  test "custom notifiers run alongside built-in notifiers" do
    RailsInformant.config.slack_webhook_url = "https://hooks.slack.com/test"
    group = create_error_group_with_occurrence

    stub_http_api

    custom = mock("custom_notifier")
    custom.expects(:should_notify?).with(group).returns(true)
    custom.expects(:notify).with(group, group.occurrences.last)

    RailsInformant.config.add_notifier custom

    RailsInformant::NotifyJob.perform_now(group)
  end

  test "updates last_notified_at when custom notifier succeeds" do
    RailsInformant.config.slack_webhook_url = nil
    group = create_error_group_with_occurrence

    custom = stub("custom_notifier", should_notify?: true, notify: nil)
    RailsInformant.config.add_notifier custom

    assert_nil group.last_notified_at
    RailsInformant::NotifyJob.perform_now(group)
    group.reload
    assert_not_nil group.last_notified_at
  end

  test "does not update last_notified_at when custom notifier raises" do
    RailsInformant.config.slack_webhook_url = nil
    group = create_error_group_with_occurrence

    custom = mock("custom_notifier")
    custom.stubs(:should_notify?).returns(true)
    custom.stubs(:notify).raises(RuntimeError, "custom notifier failed")

    RailsInformant.config.add_notifier custom

    assert_raises RuntimeError do
      RailsInformant::NotifyJob.new.perform(group)
    end
    group.reload
    assert_nil group.last_notified_at
  end
end
