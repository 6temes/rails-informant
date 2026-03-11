require "test_helper"

class RailsInformant::ErrorSubscriberTest < ActiveSupport::TestCase
  setup do
    @subscriber = RailsInformant::ErrorSubscriber.new
  end

  test "reports unhandled error" do
    error = build_error
    RailsInformant::ErrorRecorder.expects(:record).with(error, severity: "error", context: {}, source: nil)
    @subscriber.report error, handled: false, severity: :error, context: {}
  end

  test "captures handled error with error severity" do
    error = build_error
    RailsInformant::ErrorRecorder.expects(:record).with(error, severity: "error", context: {}, source: nil)
    @subscriber.report error, handled: true, severity: :error, context: {}
  end

  test "skips handled error with warning severity" do
    RailsInformant::ErrorRecorder.expects(:record).never
    @subscriber.report build_error, handled: true, severity: :warning, context: {}
  end

  test "skips handled error with info severity" do
    RailsInformant::ErrorRecorder.expects(:record).never
    @subscriber.report build_error, handled: true, severity: :info, context: {}
  end

  test "skips ignored exceptions" do
    error = ActiveRecord::RecordNotFound.new("not found")
    RailsInformant::ErrorRecorder.expects(:record).never
    @subscriber.report error, handled: false, severity: :error, context: {}
  end

  test "skips cache store sources" do
    RailsInformant::ErrorRecorder.expects(:record).never
    @subscriber.report build_error, handled: false, severity: :error, context: {},
      source: "redis_cache_store.active_support"
  end

  test "skips already captured errors" do
    error = build_error
    error.instance_variable_set(:@__rails_informant_captured, true)
    RailsInformant::ErrorRecorder.expects(:record).never
    @subscriber.report error, handled: false, severity: :error, context: {}
  end

  test "marks error as captured" do
    error = build_error
    RailsInformant::ErrorRecorder.stubs(:record)
    @subscriber.report error, handled: false, severity: :error, context: {}
    assert error.instance_variable_get(:@__rails_informant_captured)
  end

  test "skips when not initialized" do
    RailsInformant.config.capture_errors = false
    RailsInformant::ErrorRecorder.expects(:record).never
    @subscriber.report build_error, handled: false, severity: :error, context: {}
  end

  private

  def build_error
    error = StandardError.new("boom")
    error.set_backtrace [ "/app/models/user.rb:42" ]
    error
  end
end
