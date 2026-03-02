module RailsInformant
  class Configuration
    attr_accessor :capture_errors,
                  :ignored_exceptions,
                  :custom_fingerprint,
                  :max_occurrences_per_group,
                  :occurrence_cooldown,
                  :max_cause_depth,
                  :filter_parameters,
                  :exception_level_filters,
                  :current_user_method,
                  :devin_api_key,
                  :devin_playbook_id,
                  :slack_webhook_url,
                  :webhook_url,
                  :webhook_include_context,
                  :notification_cooldown,
                  :api_token,
                  :retention_days,
                  :breadcrumb_capacity,
                  :before_capture

    def initialize
      @capture_errors = true
      @ignored_exceptions = []
      @custom_fingerprint = nil
      @max_occurrences_per_group = 25
      @occurrence_cooldown = 5 # seconds; converted to duration at use site
      @max_cause_depth = 5
      @filter_parameters = []
      @exception_level_filters = {}
      @current_user_method = nil
      @devin_api_key = nil
      @devin_playbook_id = nil
      @slack_webhook_url = nil
      @webhook_url = nil
      @webhook_include_context = false
      @notification_cooldown = 3600 # seconds; converted to duration at use site
      @api_token = nil
      @retention_days = nil
      @breadcrumb_capacity = 50
      @before_capture = nil
    end

    def merge_filter_parameters(app_params)
      @filter_parameters = (Array(app_params) + Array(@filter_parameters)).uniq
    end
  end
end
