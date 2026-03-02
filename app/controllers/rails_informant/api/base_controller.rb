module RailsInformant
  module Api
    class BaseController < ActionController::API
      before_action :authenticate_token!
      before_action :set_security_headers

      rescue_from RailsInformant::InvalidParameterError do |e|
        render json: { error: e.message }, status: :bad_request
      end

      private

      def parse_time(value)
        Time.parse(value)
      rescue ArgumentError
        raise RailsInformant::InvalidParameterError, "Invalid date format: #{value}"
      end

      def authenticate_token!
        token = request.headers["Authorization"]&.delete_prefix("Bearer ")

        unless token.present? && ActiveSupport::SecurityUtils.secure_compare(token, RailsInformant.api_token.to_s)
          Rails.logger.warn "[RailsInformant] Auth failure from #{request.remote_ip} at #{Time.current.iso8601}"
          render json: { error: "Unauthorized" }, status: :unauthorized
        end
      end

      def set_security_headers
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
      end

      def paginate(scope)
        page = [ params.fetch(:page, 1).to_i, 1 ].max
        per_page = [ [ params.fetch(:per_page, 20).to_i, 1 ].max, 100 ].min

        records = scope.offset((page - 1) * per_page).limit(per_page + 1).to_a
        has_more = records.size > per_page
        records = records.first(per_page)

        { data: records, meta: { page:, per_page:, has_more: } }
      end
    end
  end
end
