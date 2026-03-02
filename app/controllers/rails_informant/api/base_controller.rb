module RailsInformant
  module Api
    class BaseController < ActionController::API
      before_action :authenticate_token!
      before_action :set_security_headers

      rescue_from RailsInformant::InvalidParameterError do |e|
        render json: { error: e.message }, status: :bad_request
      end

      rescue_from ActiveRecord::RecordInvalid do |e|
        render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end

      rescue_from ActiveRecord::RecordNotFound do
        render json: { error: "Not found" }, status: :not_found
      end

      private

      def parse_time(value)
        Time.parse(value)
      rescue ArgumentError
        raise RailsInformant::InvalidParameterError, "Invalid date format"
      end

      def authenticate_token!
        configured_token = RailsInformant.api_token

        unless configured_token.present?
          return render json: { error: "API token not configured" }, status: :service_unavailable
        end

        token = request.headers["Authorization"]&.delete_prefix("Bearer ")

        unless token.present? && ActiveSupport::SecurityUtils.secure_compare(token, configured_token)
          Rails.logger.warn "[RailsInformant] Auth failure from #{request.remote_ip} at #{Time.current.iso8601}"
          render json: { error: "Unauthorized" }, status: :unauthorized
        end
      end

      def set_security_headers
        response.headers["Cache-Control"] = "no-store"
        response.headers["Content-Security-Policy"] = "default-src 'none'"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
      end

      def paginate(scope, only:)
        page = [ params.fetch(:page, 1).to_i, 1 ].max
        per_page = [ [ params.fetch(:per_page, 20).to_i, 1 ].max, 100 ].min

        records = scope.offset((page - 1) * per_page).limit(per_page + 1).to_a
        has_more = records.size > per_page
        records = records.first(per_page)
        data = records.map { it.as_json(only:) }

        { data:, meta: { page:, per_page:, has_more: } }
      end
    end
  end
end
