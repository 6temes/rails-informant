module RailsInformant
  class Configuration
    attr_accessor :capture_errors,
                  :capture_user_email,
                  :api_token,
                  :ignored_exceptions,
                  :ignored_paths,
                  :job_attempt_threshold,
                  :retention_days,
                  :slack_webhook_url,
                  :webhook_url

    attr_writer :app_name

    def initialize
      @before_record_callbacks = []
      @api_token = ENV["INFORMANT_API_TOKEN"]
      @app_name = ENV["INFORMANT_APP_NAME"]
      @capture_errors = ENV.fetch("INFORMANT_CAPTURE_ERRORS", "true") != "false"
      @capture_user_email = false
      @custom_notifiers = []
      @ignored_exceptions = ENV["INFORMANT_IGNORED_EXCEPTIONS"]&.split(",")&.map(&:strip) || []
      @ignored_paths = ENV["INFORMANT_IGNORED_PATHS"]&.split(",")&.map(&:strip) || []
      @job_attempt_threshold = ENV["INFORMANT_JOB_ATTEMPT_THRESHOLD"]&.to_i
      @retention_days = ENV["INFORMANT_RETENTION_DAYS"]&.to_i
      @spike_protection = nil
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

    attr_reader :spike_protection

    def spike_protection=(value)
      if value && (!value.is_a?(Hash) || !value.key?(:threshold) || !value.key?(:window))
        raise ArgumentError, "spike_protection requires { threshold:, window: }"
      end
      @spike_protection = value
    end

    def before_record(&block)
      @before_record_callbacks << block
      @_frozen_callbacks = nil
    end

    def before_record_callbacks
      @_frozen_callbacks ||= @before_record_callbacks.dup.freeze
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
