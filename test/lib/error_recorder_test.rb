require "test_helper"

class RailsInformant::ErrorRecorderTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  test "records error and creates group + occurrence" do
    error = build_error

    assert_difference -> { RailsInformant::ErrorGroup.count } => 1,
                      -> { RailsInformant::Occurrence.count } => 1 do
      RailsInformant::ErrorRecorder.record error
    end

    group = RailsInformant::ErrorGroup.last
    assert_equal "StandardError", group.error_class
    assert_equal "boom", group.message
    assert_equal 1, group.total_occurrences
    assert_equal "unresolved", group.status
  end

  test "occurrence cooldown skips occurrence storage" do
    error = build_error
    RailsInformant::ErrorRecorder.record error

    # Second recording within cooldown — counter increments but no new occurrence
    assert_no_difference "RailsInformant::Occurrence.count" do
      RailsInformant::ErrorRecorder.record error
    end

    assert_equal 2, RailsInformant::ErrorGroup.last.total_occurrences
  end

  test "capture failure does not raise" do
    RailsInformant.stubs(:initialized?).returns(true)
    RailsInformant::Fingerprint.stubs(:generate).raises(RuntimeError, "bad fingerprint")

    assert_nothing_raised do
      RailsInformant::ErrorRecorder.record build_error
    end
  end

  test "exception chain captures cause" do
    inner = StandardError.new("inner error")
    inner.set_backtrace [ "/app/inner.rb:1" ]
    outer = RuntimeError.new("outer error")
    outer.set_backtrace [ "/app/outer.rb:1" ]

    # Ruby doesn't let you set cause directly, but we can test the chain builder
    begin
      begin
        raise inner
      rescue
        raise outer
      end
    rescue => error
      RailsInformant::ErrorRecorder.record error
    end

    occurrence = RailsInformant::Occurrence.last
    assert occurrence.exception_chain.present?
    assert_equal "StandardError", occurrence.exception_chain.first["class"]
  end

  test "enqueues NotifyJob when a notifier would send" do
    RailsInformant.config.slack_webhook_url = "https://hooks.slack.com/test"

    assert_enqueued_with job: RailsInformant::NotifyJob do
      RailsInformant::ErrorRecorder.record build_error
    end
  end

  test "skips NotifyJob when no notifier would send" do
    # No webhook configured — no notifiers exist
    RailsInformant.config.slack_webhook_url = nil
    RailsInformant.config.webhook_url = nil
    RailsInformant.config.reset_notifiers!

    assert_no_enqueued_jobs only: RailsInformant::NotifyJob do
      RailsInformant::ErrorRecorder.record build_error
    end
  end

  test "skips NotifyJob when notifiers exist but none would send" do
    RailsInformant.config.slack_webhook_url = "https://hooks.slack.com/test"

    # First record to create group
    RailsInformant::ErrorRecorder.record build_error
    group = RailsInformant::ErrorGroup.last
    # Mark as recently notified so should_notify? returns false
    group.update_column :last_notified_at, Time.current
    group.update_column :total_occurrences, 5

    assert_no_enqueued_jobs only: RailsInformant::NotifyJob do
      RailsInformant::ErrorRecorder.record build_error
    end
  end

  test "skips recording entirely when delivering_notification flag is set" do
    RailsInformant.config.slack_webhook_url = "https://hooks.slack.com/test"

    assert_no_difference -> { RailsInformant::ErrorGroup.count } do
      assert_no_enqueued_jobs only: RailsInformant::NotifyJob do
        RailsInformant::Current.delivering_notification = true
        RailsInformant::ErrorRecorder.record build_error
      end
    end
  ensure
    RailsInformant::Current.delivering_notification = false
  end

  test "skips recording entirely when error backtrace includes notifier path" do
    RailsInformant.config.slack_webhook_url = "https://hooks.slack.com/test"

    error = StandardError.new("SSL error")
    error.set_backtrace [
      "/gems/informant/lib/rails_informant/notifiers/notification_policy.rb:55:in `post_json'",
      "/gems/informant/lib/rails_informant/notifiers/slack.rb:7:in `notify'"
    ]

    assert_no_difference -> { RailsInformant::ErrorGroup.count } do
      assert_no_enqueued_jobs only: RailsInformant::NotifyJob do
        RailsInformant::ErrorRecorder.record error
      end
    end
  end

  test "records normally for errors not from informant" do
    RailsInformant.config.slack_webhook_url = "https://hooks.slack.com/test"

    error = StandardError.new("regular error")
    error.set_backtrace [ "/app/models/user.rb:42:in `save'" ]

    assert_enqueued_with job: RailsInformant::NotifyJob do
      RailsInformant::ErrorRecorder.record error
    end
  end

  test "trim_occurrences keeps only newest MAX_OCCURRENCES_PER_GROUP records" do
    group = create_error_group total_occurrences: 30

    # Create 30 occurrences with staggered timestamps
    30.times do |i|
      group.occurrences.create!(
        backtrace: [ "/app/test.rb:#{i}" ],
        created_at: (30 - i).minutes.ago
      )
    end

    assert_equal 30, group.occurrences.count

    RailsInformant::ErrorRecorder.send :trim_occurrences, group

    assert_equal 25, group.occurrences.count

    # The 5 oldest should be gone (created_at 30..26 minutes ago)
    remaining = group.occurrences.order(created_at: :desc).pluck(:backtrace)
    remaining.each_with_index do |bt, i|
      # Newest occurrence has index 29, next 28, etc.
      assert_equal [ "/app/test.rb:#{29 - i}" ], bt
    end
  end

  test "trim_occurrences is a no-op when at or below limit" do
    group = create_error_group total_occurrences: 25

    25.times do |i|
      group.occurrences.create!(backtrace: [ "/app/test.rb:#{i}" ])
    end

    assert_no_difference -> { group.occurrences.count } do
      RailsInformant::ErrorRecorder.send :trim_occurrences, group
    end
  end

  test "stores environment context" do
    RailsInformant::ContextBuilder.reset!
    Socket.stubs(:gethostname).returns("web-01.prod")
    RailsInformant::ErrorRecorder.record build_error

    occurrence = RailsInformant::Occurrence.last
    env_ctx = occurrence.environment_context
    assert_equal Rails.env.to_s, env_ctx["rails_env"]
    assert_equal RUBY_VERSION, env_ctx["ruby_version"]
    assert_equal "web-01.prod", env_ctx["hostname"]
    assert env_ctx["pid"].is_a?(Integer)
  ensure
    RailsInformant::ContextBuilder.reset!
  end

  test "environment context omits hostname when localhost" do
    RailsInformant::ContextBuilder.reset!
    Socket.stubs(:gethostname).returns("localhost")
    RailsInformant::ErrorRecorder.record build_error

    occurrence = RailsInformant::Occurrence.last
    env_ctx = occurrence.environment_context
    assert_nil env_ctx["hostname"]
  ensure
    RailsInformant::ContextBuilder.reset!
  end

  private

  def build_error(message = "boom")
    error = StandardError.new(message)
    error.set_backtrace [ "/app/models/user.rb:42:in `save'" ]
    error
  end
end
