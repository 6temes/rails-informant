require "rails_informant/version"
require "rails_informant/configuration"

module RailsInformant
  InvalidParameterError = Class.new(StandardError)
  NotifierError = Class.new(StandardError)

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
  autoload :ContextBuilder, "rails_informant/context_builder"
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
    autoload :NotificationPolicy, "rails_informant/notifiers/notification_policy"
    autoload :Slack, "rails_informant/notifiers/slack"
    autoload :Webhook, "rails_informant/notifiers/webhook"
  end

  mattr_accessor :config
  self.config = Configuration.new

  class << self
    delegate :api_token,
             :capture_errors,
             :capture_user_email,
             :ignored_exceptions,
             :notifiers,
             :retention_days,
             :slack_webhook_url,
             :webhook_url,
             to: :config

    def configure
      yield config
      reset_caches!
    end

    def reset_caches!
      @_initialized = nil
      @_ignored_set = nil
      config.reset_notifiers!
    end

    def initialized?
      return @_initialized if defined?(@_initialized) && @_initialized

      @_initialized = capture_errors && defined?(ActiveRecord::Base) && ActiveRecord::Base.connection_pool.with_connection { true }
    rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError
      false
    end

    def ignored_exception?(exception)
      ignored = ignored_exception_set
      exception.class.ancestors.each do |ancestor|
        name = ancestor.name or next
        return true if ignored.include?(name)
      end
      false
    end

    def current_git_sha
      @_current_git_sha ||= resolve_git_sha
    end

    def already_captured?(error)
      error.instance_variable_get(:@__rails_informant_captured)
    end

    def capture(exception, context: {}, request: nil)
      return if already_captured?(exception)
      mark_captured!(exception)
      ErrorRecorder.record exception, severity: "error", context:, env: request&.env
    end

    def mark_captured!(error)
      error.instance_variable_set(:@__rails_informant_captured, true) unless error.frozen?
    end

    def server_mode?
      defined?(Rails::Server)
    end

    private

    def ignored_exception_set
      @_ignored_set ||= Set.new(IGNORED_EXCEPTIONS_DEFAULT + Array(ignored_exceptions)).freeze
    end

    def resolve_git_sha
      GIT_SHA_SOURCES.each do |key|
        return ENV[key] if ENV[key].present?
      end

      head = Rails.root.join(".git", "HEAD").read.strip
      if head.start_with?("ref: ")
        ref = head.delete_prefix("ref: ")
        raise ArgumentError if ref.include?("..") # path traversal guard
        Rails.root.join(".git", ref).read.strip
      else
        head
      end
    rescue Errno::ENOENT, Errno::EACCES, ArgumentError
      nil
    end
  end
end

require "rails_informant/engine"
