module RailsInformant
  module Api
    class ErrorsController < BaseController
      before_action :find_error_group, only: [ :show, :update, :destroy, :fix_pending, :duplicate ]

      def index
        groups = params[:status] == "duplicate" ? ErrorGroup.all : ErrorGroup.active
        groups = groups
          .by_controller_action(params[:controller_action])
          .by_error_class(params[:error_class])
          .by_job_class(params[:job_class])
          .by_severity(params[:severity])
          .by_status(params[:status])
          .search(params[:q])
          .since(params[:since] && parse_time(params[:since]))
          .before(params[:until] && parse_time(params[:until]))
          .order(last_seen_at: :desc)

        render json: paginate(groups, only: ErrorGroup::API_FIELDS)
      end

      def show
        occurrences = @error_group.occurrences.order(created_at: :desc).limit(10)
        render json: @error_group.as_json(only: ErrorGroup::API_DETAIL_FIELDS).merge(
          recent_occurrences: occurrences.as_json(only: Occurrence::API_FIELDS)
        )
      end

      def update
        permitted = params.permit(:status, :notes)

        updates = {}
        updates[:status] = permitted[:status] if permitted[:status]
        updates[:notes] = permitted[:notes] if permitted.key?(:notes)

        @error_group.update!(updates)
        render json: @error_group.as_json(only: ErrorGroup::API_DETAIL_FIELDS)
      end

      def destroy
        if ErrorGroup.exists?(duplicate_of_id: @error_group.id)
          render json: { error: "Cannot delete: other errors reference this as a duplicate target" },
                 status: :unprocessable_entity
        else
          @error_group.destroy!
          head :no_content
        end
      end

      def fix_pending
        permitted = params.permit(:fix_sha, :original_sha, :fix_pr_url)
        @error_group.mark_as_fix_pending!(
          fix_sha: permitted[:fix_sha],
          original_sha: permitted[:original_sha],
          fix_pr_url: permitted[:fix_pr_url]
        )
        render json: @error_group.as_json(only: ErrorGroup::API_DETAIL_FIELDS)
      end

      def duplicate
        @error_group.mark_as_duplicate_of! params[:duplicate_of_id]
        render json: @error_group.as_json(only: ErrorGroup::API_DETAIL_FIELDS)
      end

      private

      def find_error_group
        @error_group = ErrorGroup.find(params[:id])
      end
    end
  end
end
