module RailsInformant
  class Configuration
    attr_accessor :capture_errors,
                  :capture_user_email,
                  :api_token,
                  :ignored_exceptions,
                  :retention_days,
                  :slack_webhook_url,
                  :webhook_url

    attr_writer :app_name

    def initialize
      @api_token = ENV["INFORMANT_API_TOKEN"]
      @app_name = ENV["INFORMANT_APP_NAME"]
      @capture_errors = ENV.fetch("INFORMANT_CAPTURE_ERRORS", "true") != "false"
      @capture_user_email = false
      @custom_notifiers = []
      @ignored_exceptions = ENV["INFORMANT_IGNORED_EXCEPTIONS"]&.split(",")&.map(&:strip) || []
      @retention_days = ENV["INFORMANT_RETENTION_DAYS"]&.to_i
      @slack_webhook_url = ENV["INFORMANT_SLACK_WEBHOOK_URL"]
      @webhook_url = ENV["INFORMANT_WEBHOOK_URL"]
    end

    def app_name
      @app_name.presence || detect_app_name
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

    def detect_app_name
      Rails.application&.class&.module_parent_name.presence || "App"
    end

    def built_in_notifiers
      [
        (Notifiers::Slack.new if slack_webhook_url.present?),
        (Notifiers::Webhook.new if webhook_url.present?)
      ].compact
    end
  end
end
