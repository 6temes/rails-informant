require "test_helper"

class RailsInformant::ErrorSubscriberTest < ActiveSupport::TestCase
  class ReportingJob < ActiveJob::Base
    def perform = Rails.error.report(RuntimeError.new("reported from a job"))
  end

  class FailingJob < ActiveJob::Base
    def perform = raise("job failed")
  end

  class InlineHelperJob < ActiveJob::Base
    def perform = nil
  end

  class OuterJob < ActiveJob::Base
    def perform
      InlineHelperJob.perform_now
      raise "outer job failed"
    end
  end

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

  test "skips a real job's failure below attempt threshold" do
    RailsInformant.config.job_attempt_threshold = 3

    assert_no_difference -> { RailsInformant::ErrorGroup.count } do
      perform_as_worker FailingJob.new
    end
  end

  test "records a real job's failure at attempt threshold" do
    RailsInformant.config.job_attempt_threshold = 3

    assert_difference -> { RailsInformant::ErrorGroup.count } => 1 do
      perform_as_worker FailingJob.new, executions: 2
    end
  end

  # A handled report never makes the job retry, so a threshold would hide it forever
  test "records a handled error reported from a job below attempt threshold" do
    RailsInformant.config.job_attempt_threshold = 3

    assert_difference -> { RailsInformant::ErrorGroup.count } => 1 do
      ReportingJob.perform_now
    end
  end

  test "records an outer job's failure after it performed another job inline" do
    RailsInformant.config.job_attempt_threshold = 3

    assert_difference -> { RailsInformant::ErrorGroup.count } => 1 do
      perform_as_worker OuterJob.new, executions: 2
    end

    assert_equal "RailsInformant::ErrorSubscriberTest::OuterJob", RailsInformant::ErrorGroup.last.job_class
  end

  test "does not attribute a later report to a job performed inline earlier" do
    Rails.application.executor.wrap do
      InlineHelperJob.perform_now
      Rails.error.report RuntimeError.new("later in the request")
    end

    assert_nil RailsInformant::ErrorGroup.last.job_class
  end

  test "records an error reported from inside a job with its job class" do
    assert_difference -> { RailsInformant::ErrorGroup.count } => 1 do
      ReportingJob.perform_now
    end

    assert_equal "RailsInformant::ErrorSubscriberTest::ReportingJob", RailsInformant::ErrorGroup.last.job_class
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

  # Runs the job the way a queue worker does: inside the executor, which reports
  # the unhandled failure. `executions` is the count before this attempt.
  def perform_as_worker(job, executions: 0)
    job.executions = executions
    Rails.application.executor.wrap(source: "application.active_job") { job.perform_now }
  rescue RuntimeError
  end

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
