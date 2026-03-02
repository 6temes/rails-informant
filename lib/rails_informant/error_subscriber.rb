module RailsInformant
  class ErrorSubscriber
    SKIP_SOURCES = /_cache_store\.active_support\z/

    def report(error, handled:, severity:, context:, source: nil)
      return unless RailsInformant.initialized?
      return if handled
      return if source && SKIP_SOURCES.match?(source)
      return if RailsInformant.ignored_exception?(error)
      return if error.instance_variable_get(:@__rails_informant_captured)

      error.instance_variable_set(:@__rails_informant_captured, true) unless error.frozen?

      ErrorRecorder.record error, severity:, context:, source:
    end
  end
end
