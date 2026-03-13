module RailsInformant
  module Api
    class DeploysController < BaseController
      STALE_ERROR_CUTOFF = 1.hour

      def create
        sha = params[:sha]
        raise RailsInformant::InvalidParameterError, "sha is required" unless sha.present?
        raise RailsInformant::InvalidParameterError, "Invalid SHA format" unless sha.match?(RailsInformant::SHA_FORMAT)

        cutoff = STALE_ERROR_CUTOFF.ago
        resolved_count = ErrorGroup
          .where(status: "unresolved")
          .where(last_seen_at: ...cutoff)
          .update_all(
            status: "resolved", resolved_at: Time.current,
            fix_sha: sha, updated_at: Time.current
          )

        render json: { resolved_count:, sha: }
      end
    end
  end
end
