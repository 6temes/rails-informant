module RailsInformant
  module Middleware
    class ErrorCapture
      def initialize(app)
        @app = app
      end

      def call(env)
        @app.call(env).tap do |status, _headers, _body|
          # Only record rescued exceptions that resulted in a server error.
          # 4xx responses are expected application errors handled by ShowExceptions.
          if (exception = env["rails_informant.rescued_exception"]) && status.to_i >= 500
            record_exception exception, env:
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
