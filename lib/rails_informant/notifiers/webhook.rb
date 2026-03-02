module RailsInformant
  module Notifiers
    class Webhook
      include NotificationPolicy

      def notify(error_group, occurrence)
        post_json \
          url: RailsInformant.webhook_url,
          body: build_payload(error_group, occurrence),
          label: "Webhook"
      end

      private

      def build_payload(error_group, occurrence)
        {
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
      end
    end
  end
end
