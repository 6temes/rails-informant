module RailsInformant
  module Notifiers
    class Slack
      include NotificationPolicy

      def notify(error_group, occurrence)
        post_json \
          url: RailsInformant.slack_webhook_url,
          body: build_payload(error_group, occurrence),
          label: "Slack webhook"
      end

      private

      def regression?(error_group)
        error_group.status == "unresolved" && error_group.fix_deployed_at.present?
      end

      def build_payload(error_group, occurrence)
        {
          text: "#{error_group.error_class}: #{error_group.message&.truncate(200)}",
          blocks: [
            header_block(error_group, occurrence),
            error_class_block(error_group),
            fields_block(error_group),
            context_block(occurrence)
          ].compact
        }
      end

      def header_block(error_group, occurrence)
        env = occurrence&.environment_context&.dig("rails_env") || Rails.env
        regression_tag = regression?(error_group) ? " [REGRESSION]" : ""
        text = "🚨 #{RailsInformant.app_name} · #{env}#{regression_tag}".truncate(150)

        {
          type: "header",
          text: { type: "plain_text", text:, emoji: true }
        }
      end

      def error_class_block(error_group)
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: "*#{error_group.error_class}*\n#{error_group.message&.truncate(200)}"
          }
        }
      end

      def fields_block(error_group)
        {
          type: "section",
          fields: [
            { type: "mrkdwn", text: "*Status:*\n#{error_group.status}" },
            { type: "mrkdwn", text: "*Occurrences:*\n#{error_group.total_occurrences}" },
            { type: "mrkdwn", text: "*First seen:*\n#{error_group.first_seen_at&.iso8601}" },
            { type: "mrkdwn", text: "*Severity:*\n#{error_group.severity}" },
            location_field(error_group)
          ].compact
        }
      end

      def location_field(error_group)
        location = error_group.controller_action || error_group.job_class || error_group.first_backtrace_line
        return unless location

        { type: "mrkdwn", text: "*Location:*\n`#{location.to_s.truncate(100)}`" }
      end

      def context_block(occurrence)
        return unless occurrence&.git_sha

        {
          type: "context",
          elements: [
            { type: "mrkdwn", text: "Deploy: `#{occurrence.git_sha[0, 7]}`" }
          ]
        }
      end
    end
  end
end
