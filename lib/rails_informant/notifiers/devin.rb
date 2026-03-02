require "net/http"
require "json"
require "uri"

module RailsInformant
  module Notifiers
    class Devin
      include NotificationPolicy

      API_URL = "https://api.devin.ai/v1/sessions".freeze

      # Override shared policy: only trigger on first occurrence.
      # Devin sessions consume ACUs — milestone re-triggers (10, 100, 1000)
      # waste resources on errors already being investigated.
      def should_notify?(error_group)
        error_group.total_occurrences == 1
      end

      def notify(error_group, occurrence)
        uri = URI.parse(API_URL)
        request = Net::HTTP::Post.new(uri, {
          "Authorization" => "Bearer #{RailsInformant.devin_api_key}",
          "Content-Type" => "application/json"
        })
        request.body = build_payload(error_group, occurrence).to_json

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.open_timeout = 10
          http.read_timeout = 15
          http.request(request)
        end

        unless response.is_a?(Net::HTTPSuccess)
          raise "Devin API error: HTTP #{response.code} — #{response.body&.to_s&.truncate(200)}"
        end
      end

      private

        def build_payload(error_group, occurrence)
          {
            playbook_id: RailsInformant.devin_playbook_id,
            prompt: build_prompt(error_group, occurrence),
            title: "Fix: #{error_group.error_class} in #{error_group.controller_action || error_group.job_class || 'unknown'}"
          }.compact
        end

        def build_prompt(error_group, occurrence)
          location = error_group.controller_action || error_group.job_class

          prompt = <<~PROMPT
            New error detected:

            Error: #{error_group.error_class} — #{error_group.message.to_s.truncate(500)}
            Severity: #{error_group.severity}
            Occurrences: #{error_group.total_occurrences}
            First seen: #{error_group.first_seen_at&.iso8601}
            Last seen: #{error_group.last_seen_at&.iso8601}
            Location: #{location}
            Error Group ID: #{error_group.id}
          PROMPT

          if occurrence
            prompt += "\nGit SHA: #{occurrence.git_sha}\n" if occurrence.git_sha
            prompt += "\nBacktrace:\n#{occurrence.backtrace&.first(5)&.map { "  #{_1}" }&.join("\n")}\n"
          end

          prompt + "\nUse the informant MCP tools to investigate (get_error id: #{error_group.id}) and fix this error."
        end
    end
  end
end
