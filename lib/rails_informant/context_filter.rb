module RailsInformant
  class ContextFilter
    MAX_BACKTRACE_FRAMES = 200
    MAX_MESSAGE_LENGTH = 2000
    MAX_CONTEXT_SIZE = 64 * 1024 # 64 KB

    class << self
      def reset!
        @_parameter_filter = nil
      end

      def filter(context)
        return nil unless context

        filtered = parameter_filter.filter(context)
        truncate_to_size(filtered)
      end

      def filter_backtrace(backtrace)
        return nil unless backtrace
        backtrace.first(MAX_BACKTRACE_FRAMES)
      end

      def filter_message(message)
        return nil unless message
        message.to_s.truncate(MAX_MESSAGE_LENGTH)
      end

      private

      def parameter_filter
        @_parameter_filter ||= ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      end

      def truncate_to_size(data)
        return data if data.is_a?(Hash) && data.size < 20

        json = data.to_json
        return data if json.bytesize <= MAX_CONTEXT_SIZE

        { _truncated: true, _original_size: json.bytesize }
      end
    end
  end
end
