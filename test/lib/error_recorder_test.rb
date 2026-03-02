require "test_helper"

class RailsInformant::ErrorRecorderTest < ActiveSupport::TestCase
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

  test "upserts same fingerprint increments counter" do
    error = build_error

    RailsInformant::ErrorRecorder.record error
    group = RailsInformant::ErrorGroup.last
    # Force last_seen_at to be old enough to pass cooldown
    group.update_column :last_seen_at, 1.minute.ago

    assert_no_difference "RailsInformant::ErrorGroup.count" do
      RailsInformant::ErrorRecorder.record error
    end

    group.reload
    assert_equal 2, group.total_occurrences
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

  test "trims occurrences beyond max" do
    RailsInformant.config.max_occurrences_per_group = 2
    RailsInformant.config.occurrence_cooldown = 0
    error = build_error

    3.times do
      RailsInformant::ErrorRecorder.record error
    end

    assert_equal 2, RailsInformant::Occurrence.count
  end

  test "before_capture can suppress error" do
    RailsInformant.config.before_capture = ->(_error, _context) { nil }

    assert_no_difference "RailsInformant::ErrorGroup.count" do
      RailsInformant::ErrorRecorder.record build_error
    end
  end

  test "before_capture can modify context" do
    RailsInformant.config.before_capture = ->(_error, context) {
      context.merge(custom_key: "custom_value")
    }

    RailsInformant::ErrorRecorder.record build_error
    assert_equal 1, RailsInformant::ErrorGroup.count
  end

  test "exception level filters override severity" do
    RailsInformant.config.exception_level_filters = { "StandardError" => "warning" }
    RailsInformant::ErrorRecorder.record build_error

    group = RailsInformant::ErrorGroup.last
    assert_equal "warning", group.severity
  end

  test "resolved error is reopened on regression" do
    error = build_error
    RailsInformant::ErrorRecorder.record error

    group = RailsInformant::ErrorGroup.last
    group.update_columns status: "resolved", resolved_at: Time.current, last_seen_at: 1.minute.ago

    RailsInformant::ErrorRecorder.record error
    group.reload

    assert_equal "unresolved", group.status
    assert_nil group.resolved_at
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

  test "stores environment context" do
    RailsInformant::ErrorRecorder.record build_error

    occurrence = RailsInformant::Occurrence.last
    env_ctx = occurrence.environment_context
    assert_equal Rails.env.to_s, env_ctx["rails_env"]
    assert_equal RUBY_VERSION, env_ctx["ruby_version"]
    assert env_ctx["hostname"].present?
    assert env_ctx["pid"].is_a?(Integer)
  end

  private

  def build_error(message = "boom")
    error = StandardError.new(message)
    error.set_backtrace [ "/app/models/user.rb:42:in `save'" ]
    error
  end
end
