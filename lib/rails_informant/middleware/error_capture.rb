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
        return if RailsInformant.already_captured?(exception)
        RailsInformant.mark_captured!(exception)
        ErrorRecorder.record(exception, env: env)
      end
    end
  end
end
