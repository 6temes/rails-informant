require "net/http"
require "json"
require "uri"

module RailsInformant
  module Notifiers
    class Webhook
      include NotificationPolicy

      def notify(error_group, occurrence)
        uri = URI.parse(RailsInformant.webhook_url)
        payload = build_payload(error_group, occurrence)
        Net::HTTP.post(uri, payload.to_json, "Content-Type" => "application/json")
      end

      private

      def build_payload(error_group, occurrence)
        payload = {
          error_class: error_group.error_class,
          fingerprint: error_group.fingerprint,
          message: error_group.message,
          severity: error_group.severity,
          status: error_group.status,
          total_occurrences: error_group.total_occurrences,
          controller_action: error_group.controller_action,
          job_class: error_group.job_class,
          first_seen_at: error_group.first_seen_at&.iso8601,
          last_seen_at: error_group.last_seen_at&.iso8601
        }

        if RailsInformant.webhook_include_context && occurrence
          payload[:occurrence] = {
            backtrace: occurrence.backtrace&.first(10),
            environment_context: occurrence.environment_context,
            git_sha: occurrence.git_sha
          }
        end

        payload
      end
    end
  end
end
