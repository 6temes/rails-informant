require "net/http"
require "json"
require "uri"

module RailsInformant
  module Notifiers
    class Slack
      include NotificationPolicy

      def notify(error_group, occurrence)
        uri = URI.parse(RailsInformant.slack_webhook_url)
        payload = build_payload(error_group, occurrence)
        Net::HTTP.post(uri, payload.to_json, "Content-Type" => "application/json")
      end

      private

      def regression?(error_group)
        error_group.status == "unresolved" && error_group.fix_deployed_at.present?
      end

      def build_payload(error_group, occurrence)
        regression_tag = regression?(error_group) ? " [REGRESSION]" : ""

        {
          blocks: [
            {
              type: "header",
              text: {
                type: "plain_text",
                text: "#{error_group.error_class}#{regression_tag}",
                emoji: true
              }
            },
            {
              type: "section",
              fields: [
                { type: "mrkdwn", text: "*Message:*\n#{truncate(error_group.message, 200)}" },
                { type: "mrkdwn", text: "*Status:*\n#{error_group.status}" },
                { type: "mrkdwn", text: "*Occurrences:*\n#{error_group.total_occurrences}" },
                { type: "mrkdwn", text: "*First seen:*\n#{error_group.first_seen_at&.iso8601}" }
              ]
            },
            {
              type: "section",
              fields: [
                location_field(error_group),
                { type: "mrkdwn", text: "*Severity:*\n#{error_group.severity}" }
              ].compact
            },
            context_block(occurrence)
          ].compact
        }
      end

      def location_field(error_group)
        location = error_group.controller_action || error_group.job_class || error_group.first_backtrace_line
        return unless location

        { type: "mrkdwn", text: "*Location:*\n`#{truncate(location, 100)}`" }
      end

      def context_block(occurrence)
        return unless occurrence

        elements = []
        if occurrence.git_sha
          elements << { type: "mrkdwn", text: "Deploy: `#{occurrence.git_sha[0..7]}`" }
        end
        if occurrence.environment_context&.dig("hostname")
          elements << { type: "mrkdwn", text: "Host: `#{occurrence.environment_context["hostname"]}`" }
        end

        return if elements.empty?

        { type: "context", elements: elements }
      end

      def truncate(text, length)
        return "" unless text
        text.length > length ? "#{text[0...length]}..." : text
      end
    end
  end
end
