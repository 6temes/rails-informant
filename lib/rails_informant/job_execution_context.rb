module RailsInformant
  # Rails leaves ExecutionContext[:job] set after perform_now returns, so a job
  # performed inline would claim every later report in the same request or job.
  # A failing job stays in place so the executor's report still names it.
  module JobExecutionContext
    def perform_now
      previous = ActiveSupport::ExecutionContext.to_h[:job]
      super.tap { ActiveSupport::ExecutionContext[:job] = previous }
    end
  end
end
