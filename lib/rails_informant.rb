require "rails_informant/version"
require "rails_informant/configuration"

module RailsInformant
  InvalidParameterError = Class.new(StandardError)

  IGNORED_EXCEPTIONS_DEFAULT = %w[
    AbstractController::ActionNotFound
    ActionController::BadRequest
    ActionController::InvalidAuthenticityToken
    ActionController::InvalidCrossOriginRequest
    ActionController::MethodNotAllowed
    ActionController::NotImplemented
    ActionController::ParameterMissing
    ActionController::RoutingError
    ActionController::UnknownAction
    ActionController::UnknownFormat
    ActionController::UnknownHttpMethod
    ActionController::UrlGenerationError
    ActionDispatch::Http::MimeNegotiation::InvalidType
    ActiveRecord::RecordNotFound
    CGI::Session::CookieStore::TamperedWithCookie
    Mime::Type::InvalidMimeType
    Rack::QueryParser::InvalidParameterError
    Rack::QueryParser::ParameterTypeError
    Rack::Utils::InvalidParameterError
    SignalException
    SystemExit
  ].freeze

  GIT_SHA_SOURCES = %w[GIT_SHA REVISION KAMAL_VERSION].freeze

  autoload :BreadcrumbBuffer, "rails_informant/breadcrumb_buffer"
  autoload :BreadcrumbSubscriber, "rails_informant/breadcrumb_subscriber"
  autoload :ContextFilter, "rails_informant/context_filter"
  autoload :Current, "rails_informant/current"
  autoload :ErrorRecorder, "rails_informant/error_recorder"
  autoload :ErrorSubscriber, "rails_informant/error_subscriber"
  autoload :Fingerprint, "rails_informant/fingerprint"
  autoload :StructuredEventSubscriber, "rails_informant/structured_event_subscriber"

  module Middleware
    autoload :ErrorCapture, "rails_informant/middleware/error_capture"
    autoload :RescuedExceptionInterceptor, "rails_informant/middleware/rescued_exception_interceptor"
  end

  module Notifiers
    autoload :Devin, "rails_informant/notifiers/devin"
    autoload :NotificationPolicy, "rails_informant/notifiers/notification_policy"
    autoload :Slack, "rails_informant/notifiers/slack"
    autoload :Webhook, "rails_informant/notifiers/webhook"
  end

  mattr_accessor :config
  self.config = Configuration.new

  class << self
    delegate :capture_errors,
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
             :before_capture,
             to: :config

    def configure
      yield config
    end

    def initialized?
      capture_errors && defined?(ActiveRecord::Base) && ActiveRecord::Base.connection_pool.connected?
    rescue ActiveRecord::ConnectionNotEstablished
      false
    end

    def ignored_exception?(exception)
      all_ignored = IGNORED_EXCEPTIONS_DEFAULT + Array(ignored_exceptions)
      ancestor_names = exception.class.ancestors.map(&:name).compact

      all_ignored.any? do |ignored|
        case ignored
        when Regexp
          ancestor_names.any? { _1.match?(ignored) }
        else
          ancestor_names.include?(ignored.to_s)
        end
      end
    end

    def current_git_sha
      @_current_git_sha ||= resolve_git_sha
    end

    def capture(exception, context: {})
      ErrorRecorder.record exception, severity: "error", context:
    end

    def server_mode?
      defined?(Rails::Server) || defined?(Puma) || defined?(Unicorn) || defined?(Passenger)
    end

    private

    def resolve_git_sha
      GIT_SHA_SOURCES.each do |key|
        return ENV[key] if ENV[key].present?
      end

      git_head = Rails.root.join(".git", "HEAD")
      return unless git_head.exist?

      content = git_head.read.strip
      if content.start_with?("ref: ")
        ref_path = Rails.root.join(".git", content.delete_prefix("ref: "))
        ref_path.exist? ? ref_path.read.strip : nil
      else
        content
      end
    rescue Errno::ENOENT, Errno::EACCES
      nil
    end
  end
end

require "rails_informant/engine"
