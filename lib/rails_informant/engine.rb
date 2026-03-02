module RailsInformant
  class Engine < ::Rails::Engine
    isolate_namespace RailsInformant

    initializer "rails_informant.error_subscriber" do
      Rails.error.subscribe RailsInformant::ErrorSubscriber.new
    end

    initializer "rails_informant.context_middleware" do
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
      RailsInformant::BreadcrumbSubscriber.subscribe!
    end

    initializer "rails_informant.structured_events" do
      Rails.event.subscribe(
        RailsInformant::StructuredEventSubscriber.new
      )
    end

    initializer "rails_informant.detect_deploy" do
      config.after_initialize do
        next unless RailsInformant.server_mode?

        current_sha = RailsInformant.current_git_sha
        next unless current_sha

        RailsInformant::ErrorGroup
          .where(status: "fix_pending")
          .where.not(original_sha: current_sha)
          .update_all(status: "resolved", resolved_at: Time.current, fix_deployed_at: Time.current, updated_at: Time.current)
      rescue ActiveRecord::StatementInvalid
        # Table may not exist yet during initial migration
      end
    end

    config.after_initialize do
      RailsInformant.config.merge_filter_parameters(
        Rails.application.config.filter_parameters
      )
    end
  end
end
