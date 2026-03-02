module RailsInformant
  class ContextFilter
    MAX_BACKTRACE_FRAMES = 200
    MAX_MESSAGE_LENGTH = 2000
    MAX_CONTEXT_SIZE = 64 * 1024 # 64 KB

    class << self
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
        @_parameter_filter = nil if filter_params_changed?
        @_parameter_filter ||= begin
          @_last_filter_params = current_filter_params.dup
          ActiveSupport::ParameterFilter.new(current_filter_params)
        end
      end

      def current_filter_params
        RailsInformant.filter_parameters
      end

      def filter_params_changed?
        @_last_filter_params != current_filter_params
      end

      def truncate_to_size(data)
        json = data.to_json
        return data if json.bytesize <= MAX_CONTEXT_SIZE

        { _truncated: true, _original_size: json.bytesize }
      end
    end
  end
end
