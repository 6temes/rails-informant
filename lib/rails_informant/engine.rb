module RailsInformant
  class Engine < ::Rails::Engine
    isolate_namespace RailsInformant

    initializer "rails_informant.error_subscriber" do
      next unless RailsInformant.capture_errors

      Rails.error.subscribe RailsInformant::ErrorSubscriber.new
    end

    initializer "rails_informant.context_middleware" do
      next unless RailsInformant.capture_errors

      Rails.error.add_middleware ->(error, context) {
        context.merge deploy_sha: RailsInformant.current_git_sha
      }
    end

    initializer "rails_informant.middleware" do |app|
      next unless RailsInformant.capture_errors

      app.middleware.insert_before ActionDispatch::ShowExceptions,
        RailsInformant::Middleware::ErrorCapture
      app.middleware.insert_after ActionDispatch::DebugExceptions,
        RailsInformant::Middleware::RescuedExceptionInterceptor
    end

    initializer "rails_informant.breadcrumbs" do
      next unless RailsInformant.capture_errors

      RailsInformant::BreadcrumbSubscriber.subscribe!
    end

    initializer "rails_informant.structured_events" do
      next unless RailsInformant.capture_errors

      Rails.event.subscribe(
        RailsInformant::StructuredEventSubscriber.new
      )
    end

    initializer "rails_informant.detect_deploy" do
      config.after_initialize do
        next unless RailsInformant.server_mode?

        current_sha = RailsInformant.current_git_sha
        next unless current_sha

        now = Time.current
        RailsInformant::ErrorGroup
          .where(status: "fix_pending")
          .where.not(original_sha: current_sha)
          .in_batches(of: 100)
          .update_all(status: "resolved", resolved_at: now, fix_deployed_at: now, updated_at: now)
      rescue ActiveRecord::StatementInvalid
        # Table may not exist yet during initial migration
      end
    end

    initializer "rails_informant.validate_api_token" do
      config.after_initialize { RailsInformant::Engine.validate_api_token! }
    end

    MINIMUM_TOKEN_LENGTH = 32

    def self.validate_api_token!
      return unless RailsInformant.capture_errors

      token = RailsInformant.api_token

      if token.nil?
        raise <<~MSG.squish
          RailsInformant: api_token must be configured when capture_errors is enabled.
          Set it in your initializer: config.api_token = "your-secret-token"
        MSG
      end

      if token.length < MINIMUM_TOKEN_LENGTH
        raise <<~MSG.squish
          RailsInformant: api_token must be at least #{MINIMUM_TOKEN_LENGTH} characters.
          Use SecureRandom.hex(32) or Rails credentials to generate a secure token.
        MSG
      end
    end
  end
end
