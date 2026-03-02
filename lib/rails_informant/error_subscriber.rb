module RailsInformant
  class ErrorSubscriber
    SKIP_SOURCES = /_cache_store\.active_support\z/

    def report(error, handled:, severity:, context:, source: nil)
      return unless RailsInformant.initialized?
      return if handled
      return if source && SKIP_SOURCES.match?(source)
      return if RailsInformant.ignored_exception?(error)
      return if RailsInformant.already_captured?(error)

      RailsInformant.mark_captured!(error)

      ErrorRecorder.record error, severity:, context:, source:
    end
  end
end
