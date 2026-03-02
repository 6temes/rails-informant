module RailsInformant
  module Middleware
    class ErrorCapture
      def initialize(app)
        @app = app
      end

      def call(env)
        @app.call(env).tap do
          if (exception = env["rails_informant.rescued_exception"])
            record_exception(exception, env: env)
          end
        end
      rescue StandardError => exception
        record_exception(exception, env: env)
        raise
      end

      private

      def record_exception(exception, env:)
        return if exception.instance_variable_get(:@__rails_informant_captured)
        exception.instance_variable_set(:@__rails_informant_captured, true) unless exception.frozen?
        ErrorRecorder.record(exception, env: env)
      end
    end
  end
end
