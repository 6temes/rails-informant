require "test_helper"
require "net/http"

class RailsInformant::ConfigurationTest < ActiveSupport::TestCase
  test "capture_user_email defaults to false" do
    config = RailsInformant::Configuration.new
    assert_equal false, config.capture_user_email
  end

  test "capture_user_email can be enabled" do
    config = RailsInformant::Configuration.new
    config.capture_user_email = true
    assert_equal true, config.capture_user_email
  end

  test "notifiers returns empty array when nothing configured" do
    config = RailsInformant::Configuration.new
    config.slack_webhook_url = nil
    config.webhook_url = nil
    config.devin_api_key = nil
    config.devin_playbook_id = nil

    assert_equal [], config.notifiers
  end

  test "notifiers includes Slack when slack_webhook_url configured" do
    config = RailsInformant::Configuration.new
    config.slack_webhook_url = "https://hooks.slack.com/test"
    config.webhook_url = nil
    config.devin_api_key = nil

    assert_equal 1, config.notifiers.size
    assert_kind_of RailsInformant::Notifiers::Slack, config.notifiers.first
  end

  test "notifiers includes Webhook when webhook_url configured" do
    config = RailsInformant::Configuration.new
    config.webhook_url = "https://example.com/webhook"
    config.slack_webhook_url = nil
    config.devin_api_key = nil

    assert_equal 1, config.notifiers.size
    assert_kind_of RailsInformant::Notifiers::Webhook, config.notifiers.first
  end

  test "notifiers includes Devin when api_key and playbook_id configured" do
    config = RailsInformant::Configuration.new
    config.devin_api_key = "key-123"
    config.devin_playbook_id = "pb-456"
    config.slack_webhook_url = nil
    config.webhook_url = nil

    assert_equal 1, config.notifiers.size
    assert_kind_of RailsInformant::Notifiers::Devin, config.notifiers.first
  end

  test "notifiers excludes Devin when only api_key configured" do
    config = RailsInformant::Configuration.new
    config.devin_api_key = "key-123"
    config.devin_playbook_id = nil
    config.slack_webhook_url = nil
    config.webhook_url = nil

    assert_equal [], config.notifiers
  end

  test "add_notifier appends custom notifier" do
    config = RailsInformant::Configuration.new
    config.slack_webhook_url = nil
    config.webhook_url = nil
    config.devin_api_key = nil

    custom = Object.new
    config.add_notifier custom

    assert_equal [ custom ], config.notifiers
  end

  test "custom notifiers appear after built-in notifiers" do
    config = RailsInformant::Configuration.new
    config.slack_webhook_url = "https://hooks.slack.com/test"
    config.webhook_url = nil
    config.devin_api_key = nil

    custom = Object.new
    config.add_notifier custom

    notifiers = config.notifiers
    assert_equal 2, notifiers.size
    assert_kind_of RailsInformant::Notifiers::Slack, notifiers.first
    assert_same custom, notifiers.last
  end

  test "multiple custom notifiers can be registered" do
    config = RailsInformant::Configuration.new
    config.slack_webhook_url = nil
    config.webhook_url = nil
    config.devin_api_key = nil

    first = Object.new
    second = Object.new
    config.add_notifier first
    config.add_notifier second

    assert_equal [ first, second ], config.notifiers
  end

  test "reads api_token from ENV" do
    ENV["INFORMANT_API_TOKEN"] = "env-token-00112233445566778899aabb"
    config = RailsInformant::Configuration.new
    assert_equal "env-token-00112233445566778899aabb", config.api_token
  ensure
    ENV.delete("INFORMANT_API_TOKEN")
  end

  test "capture_errors defaults to true" do
    config = RailsInformant::Configuration.new
    assert_equal true, config.capture_errors
  end

  test "capture_errors reads false from ENV" do
    ENV["INFORMANT_CAPTURE_ERRORS"] = "false"
    config = RailsInformant::Configuration.new
    assert_equal false, config.capture_errors
  ensure
    ENV.delete("INFORMANT_CAPTURE_ERRORS")
  end

  test "retention_days reads from ENV" do
    ENV["INFORMANT_RETENTION_DAYS"] = "90"
    config = RailsInformant::Configuration.new
    assert_equal 90, config.retention_days
  ensure
    ENV.delete("INFORMANT_RETENTION_DAYS")
  end

  test "ignored_exceptions reads comma-separated list from ENV" do
    ENV["INFORMANT_IGNORED_EXCEPTIONS"] = "MyApp::NotFound, MyApp::Forbidden"
    config = RailsInformant::Configuration.new
    assert_equal [ "MyApp::NotFound", "MyApp::Forbidden" ], config.ignored_exceptions
  ensure
    ENV.delete("INFORMANT_IGNORED_EXCEPTIONS")
  end

  test "custom notifiers survive config reset" do
    RailsInformant.config.slack_webhook_url = nil
    RailsInformant.config.webhook_url = nil
    RailsInformant.config.devin_api_key = nil

    custom = Object.new
    RailsInformant.config.add_notifier custom

    assert_includes RailsInformant.config.notifiers, custom
  end
end
