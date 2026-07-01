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

    initializer "rails_informant.log_pending_fixes" do
      config.after_initialize do
        next unless RailsInformant.server_mode?

        count = RailsInformant::ErrorGroup.where(status: "fix_pending").count
        next if count.zero?

        Rails.logger.info "[Informant] #{count} error(s) awaiting fix verification"
      rescue ActiveRecord::StatementInvalid
        # Table may not exist yet during initial migration
      end
    end

    initializer "rails_informant.validate_api_token" do
      config.after_initialize { RailsInformant::Engine.validate_api_token! }
    end

    initializer "rails_informant.check_integration_drift" do
      config.after_initialize { RailsInformant::Engine.check_integration_drift! }
    end

    # Dev-only, warn-only nudge: when the committed .claude/ integration has
    # drifted from what the installed gem would generate now, log the one-command
    # fix and refresh the drift flag the hook reads. Silent when current,
    # not_installed, error, or in production; never raises out (a drift check must
    # not break boot).
    def self.check_integration_drift!
      return unless Rails.env.development? && (RailsInformant.server_mode? || RailsInformant.console_mode?)

      integration = RailsInformant::Integration.new
      status = integration.status
      integration.write_drift_flag stale: status == :stale

      return unless status == :stale

      Rails.logger&.warn <<~MSG.squish
        [Informant] Your Claude Code integration is out of date — the installed
        gem would generate different .claude/ files than this app has committed.
        Run `bin/rails g rails_informant:skill` to update it.
      MSG
    rescue StandardError
      # Never break boot over a drift check.
    end

    MINIMUM_TOKEN_LENGTH = 32

    def self.validate_api_token!
      return unless RailsInformant.capture_errors

      token = RailsInformant.api_token

      message = if token.nil?
        <<~MSG.squish
          RailsInformant: api_token must be configured when capture_errors is enabled.
          Set it in your initializer: config.api_token = "your-secret-token"
        MSG
      elsif token.length < MINIMUM_TOKEN_LENGTH
        <<~MSG.squish
          RailsInformant: api_token must be at least #{MINIMUM_TOKEN_LENGTH} characters.
          Use SecureRandom.hex(32) or Rails credentials to generate a secure token.
        MSG
      end

      return unless message

      if RailsInformant.server_mode?
        raise message
      else
        Rails.logger&.warn message
      end
    end
  end
end
