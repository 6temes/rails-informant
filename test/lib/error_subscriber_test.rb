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

  test "captures handled error with warning severity" do
    error = build_error
    RailsInformant::ErrorRecorder.expects(:record).with(error, severity: "warning", context: {}, source: nil)
    @subscriber.report error, handled: true, severity: :warning, context: {}
  end

  test "skips handled error with info severity" do
    RailsInformant::ErrorRecorder.expects(:record).never
    @subscriber.report build_error, handled: true, severity: :info, context: {}
  end

  test "skips ignored exceptions" do
    error = SystemExit.new("shutting down")
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

  test "skips job error below attempt threshold" do
    RailsInformant.config.job_attempt_threshold = 3
    RailsInformant::ErrorRecorder.expects(:record).never
    @subscriber.report build_error, handled: false, severity: :error,
      context: { job: { class: "MyJob", executions: 1 } }
  end

  test "records job error at or above attempt threshold" do
    RailsInformant.config.job_attempt_threshold = 3
    RailsInformant::ErrorRecorder.expects(:record).once
    @subscriber.report build_error, handled: false, severity: :error,
      context: { job: { class: "MyJob", executions: 3 } }
  end

  test "records all errors when job_attempt_threshold is nil" do
    RailsInformant.config.job_attempt_threshold = nil
    RailsInformant::ErrorRecorder.expects(:record).once
    @subscriber.report build_error, handled: false, severity: :error,
      context: { job: { class: "MyJob", executions: 1 } }
  end

  test "skips when silenced" do
    RailsInformant::Current.silenced = true
    RailsInformant::ErrorRecorder.expects(:record).never
    @subscriber.report build_error, handled: false, severity: :error, context: {}
  end

  test "skips when not initialized" do
    RailsInformant.config.capture_errors = false
    RailsInformant::ErrorRecorder.expects(:record).never
    @subscriber.report build_error, handled: false, severity: :error, context: {}
  end

  # The incident: a background-job DeserializationError wrapping a RecordNotFound
  # must be recorded. Asserts through the real model, not a mocked ErrorRecorder.
  test "records a job DeserializationError whose cause is RecordNotFound" do
    error = deserialization_error_caused_by_record_not_found

    assert_difference -> { RailsInformant::ErrorGroup.count } => 1,
                      -> { RailsInformant::Occurrence.count } => 1 do
      @subscriber.report error, handled: false, severity: :error, context: {}
    end

    assert_equal "ActiveJob::DeserializationError", RailsInformant::ErrorGroup.last.error_class
  end

  private

  def build_error
    error = StandardError.new("boom")
    error.set_backtrace [ "/app/models/user.rb:42" ]
    error
  end

  def deserialization_error_caused_by_record_not_found
    begin
      raise ActiveRecord::RecordNotFound, "Couldn't find User with 'id'=999"
    rescue
      raise ActiveJob::DeserializationError
    end
  rescue ActiveJob::DeserializationError => error
    error
  end
end
