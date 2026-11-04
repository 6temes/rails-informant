module RailsInformant
  module Api
    class StatusController < BaseController
      def show
        counts = ErrorGroup.group(:status).count
        render json: {
          duplicate_count: counts.fetch("duplicate", 0),
          fix_pending_count: counts.fetch("fix_pending", 0),
          ignored_count: counts.fetch("ignored", 0),
          resolved_count: counts.fetch("resolved", 0),
          unresolved_count: counts.fetch("unresolved", 0),
          deploy_sha: RailsInformant.current_git_sha,
          top_errors: top_errors,
          **browser_group_limit
        }
      end

      private

      def browser_group_limit
        return {} unless RailsInformant.config.capture_browser_errors && RailsInformant.browser_schema_ready?

        {
          browser_groups_created_this_hour: ErrorGroup.browser_created_this_hour.count,
          browser_new_group_limit: RailsInformant.config.browser_new_group_limit
        }
      end

      def top_errors
        ErrorGroup
          .where(status: "unresolved")
          .order(total_occurrences: :desc)
          .limit(5)
          .select(:id, :error_class, :message, :total_occurrences)
          .map { |g| { id: g.id, error_class: g.error_class, message: g.message&.truncate(100), total_occurrences: g.total_occurrences } }
      end
    end
  end
end
