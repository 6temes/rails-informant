module RailsInformant
  module Api
    class ErrorsController < BaseController
      before_action :find_error_group, only: [ :show, :update, :destroy, :fix_pending, :duplicate ]

      def index
        groups = ErrorGroup.active.order(last_seen_at: :desc)
        groups = groups.where(status: params[:status]) if params[:status]
        groups = groups.where(error_class: params[:error_class]) if params[:error_class]
        groups = groups.where(last_seen_at: parse_time(params[:since])..) if params[:since]
        groups = groups.where(last_seen_at: ..parse_time(params[:until])) if params[:until]
        if params[:q]
          groups = groups.where("message LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%")
        end

        render json: paginate(groups)
      end

      def show
        occurrences = @error_group.occurrences.order(created_at: :desc).limit(10)
        render json: @error_group.as_json.merge(recent_occurrences: occurrences.as_json)
      end

      def update
        permitted = params.permit(:status, :notes)

        if permitted[:status] && !ErrorGroup::VALID_TRANSITIONS[@error_group.status]&.include?(permitted[:status])
          return render json: { error: "Invalid transition from #{@error_group.status} to #{permitted[:status]}" },
            status: :unprocessable_entity
        end

        updates = {}
        updates[:status] = permitted[:status] if permitted[:status]
        updates[:notes] = permitted[:notes] if permitted.key?(:notes)
        updates[:resolved_at] = Time.current if permitted[:status] == "resolved"

        @error_group.update!(updates)
        render json: @error_group
      end

      def destroy
        @error_group.destroy!
        head :no_content
      end

      def fix_pending
        unless params[:fix_sha].present? && params[:original_sha].present?
          return render json: { error: "fix_sha and original_sha are required" }, status: :unprocessable_entity
        end

        unless ErrorGroup::VALID_TRANSITIONS[@error_group.status]&.include?("fix_pending")
          return render json: { error: "Cannot transition from #{@error_group.status} to fix_pending" },
            status: :unprocessable_entity
        end

        @error_group.update!(
          status: "fix_pending",
          fix_sha: params[:fix_sha],
          original_sha: params[:original_sha],
          fix_pr_url: params[:fix_pr_url]
        )
        render json: @error_group
      end

      def duplicate
        unless params[:duplicate_of_id].present?
          return render json: { error: "duplicate_of_id is required" }, status: :unprocessable_entity
        end

        target = ErrorGroup.find_by(id: params[:duplicate_of_id])
        unless target
          return render json: { error: "Target error group not found" }, status: :not_found
        end

        if target.id == @error_group.id
          return render json: { error: "Cannot mark as duplicate of itself" }, status: :unprocessable_entity
        end

        if circular_duplicate?(target, @error_group.id)
          return render json: { error: "Circular duplicate chain detected" }, status: :unprocessable_entity
        end

        @error_group.update!(status: "duplicate", duplicate_of: target)
        render json: @error_group
      end

      private

      def find_error_group
        @error_group = ErrorGroup.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end

      def circular_duplicate?(target, original_id, depth: 0)
        return true if depth > 10
        return false unless target&.duplicate_of_id

        target.duplicate_of_id == original_id ||
          circular_duplicate?(ErrorGroup.find_by(id: target.duplicate_of_id), original_id, depth: depth + 1)
      end
    end
  end
end
