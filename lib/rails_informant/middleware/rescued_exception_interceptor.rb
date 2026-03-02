module RailsInformant
  module Middleware
    class RescuedExceptionInterceptor
      def initialize(app)
        @app = app
      end

      def call(env)
        @app.call(env)
      rescue StandardError => exception
        env["rails_informant.rescued_exception"] = exception
        raise
      end
    end
  end
end
