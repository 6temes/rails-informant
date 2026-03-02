module RailsInformant
  module Api
    class OccurrencesController < BaseController
      def index
        occurrences = Occurrence.order(created_at: :desc)
        occurrences = occurrences.where(error_group_id: params[:error_group_id]) if params[:error_group_id]
        occurrences = occurrences.where(created_at: parse_time(params[:since])..) if params[:since]
        occurrences = occurrences.where(created_at: ..parse_time(params[:until])) if params[:until]

        render json: paginate(occurrences)
      end
    end
  end
end
