module RailsInformant
  class ErrorSubscriber
    SKIP_SOURCES = /_cache_store\.active_support\z/

    def report(error, handled:, severity:, context:, source: nil)
      return unless RailsInformant.initialized?
      return if handled && severity == :info
      return if source && SKIP_SOURCES.match?(source)
      return if RailsInformant::Current.silenced
      return if below_job_attempt_threshold?(context)
      return if RailsInformant.ignored_exception?(error)
      return if RailsInformant.already_captured?(error)

      RailsInformant.mark_captured!(error)

      ErrorRecorder.record error, severity: severity.to_s, context:, source:
    end

    private

    def below_job_attempt_threshold?(context)
      threshold = RailsInformant.config.job_attempt_threshold
      return false unless threshold

      case context
      in job: { executions: Integer => executions }
        executions < threshold
      in executions: Integer => executions
        executions < threshold
      else
        false
      end
    end
  end
end
