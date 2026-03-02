module RailsInformant
  class Configuration
    attr_accessor :api_token,
                  :capture_errors,
                  :capture_user_email,
                  :devin_api_key,
                  :devin_playbook_id,
                  :ignored_exceptions,
                  :retention_days,
                  :slack_webhook_url,
                  :webhook_url

    def initialize
      @api_token = ENV["INFORMANT_API_TOKEN"]
      @capture_errors = ENV.fetch("INFORMANT_CAPTURE_ERRORS", "true") != "false"
      @capture_user_email = false
      @custom_notifiers = []
      @devin_api_key = ENV["INFORMANT_DEVIN_API_KEY"]
      @devin_playbook_id = ENV["INFORMANT_DEVIN_PLAYBOOK_ID"]
      @ignored_exceptions = ENV["INFORMANT_IGNORED_EXCEPTIONS"]&.split(",")&.map(&:strip) || []
      @retention_days = ENV["INFORMANT_RETENTION_DAYS"]&.to_i
      @slack_webhook_url = ENV["INFORMANT_SLACK_WEBHOOK_URL"]
      @webhook_url = ENV["INFORMANT_WEBHOOK_URL"]
    end

    # Returns all notifiers: built-in (auto-registered from config) + custom.
    def notifiers
      @_notifiers ||= built_in_notifiers + @custom_notifiers
    end

    # Register a custom notifier. Must respond to #notify and #should_notify?.
    def add_notifier(notifier)
      @custom_notifiers << notifier
      @_notifiers = nil
    end

    def reset_notifiers!
      @_notifiers = nil
    end

    private

    def built_in_notifiers
      [
        (Notifiers::Devin.new if devin_api_key.present? && devin_playbook_id.present?),
        (Notifiers::Slack.new if slack_webhook_url.present?),
        (Notifiers::Webhook.new if webhook_url.present?)
      ].compact
    end
  end
end
