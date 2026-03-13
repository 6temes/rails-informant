module RailsInformant
  class ContextBuilder
    MAX_CAUSE_DEPTH = 5
    SKIP_HEADERS = Set.new(%w[
      HTTP_AUTHORIZATION
      HTTP_COOKIE
      HTTP_PROXY_AUTHORIZATION
      HTTP_X_API_KEY
      HTTP_X_AUTH_TOKEN
      HTTP_X_CSRF_TOKEN
    ]).freeze

    class << self
      def build_exception_chain(error)
        chain = []
        current = error.cause
        depth = 0

        while current && depth < MAX_CAUSE_DEPTH
          chain << {
            class: current.class.name,
            message: ContextFilter.filter_message(current.message),
            backtrace: ContextFilter.filter_backtrace(current.backtrace)
          }
          current = current.cause
          depth += 1
        end

        chain.presence
      end

      def build_request_context(env)
        return unless env

        request = ActionDispatch::Request.new(env)
        ctx = {
          url: filtered_url(request.original_url),
          method: request.request_method,
          params: request.filtered_parameters,
          headers: extract_headers(request),
          ip: request.remote_ip
        }

        ContextFilter.filter(ctx)
      end

      def build_user_context(env)
        ctx = RailsInformant::Current.user_context || detect_current_user(env)
        ContextFilter.filter(ctx)
      end

      def build_environment_context
        @_static_env ||= begin
          hostname = Socket.gethostname
          env = {
            rails_env: Rails.env.to_s,
            ruby_version: RUBY_VERSION,
            rails_version: Rails::VERSION::STRING
          }
          env[:hostname] = hostname unless hostname == "localhost"
          env.freeze
        end
        @_static_env.merge(pid: Process.pid)
      end

      def reset!
        @_static_env = nil
      end

      def group_attributes(error, severity:, context:, env:, now:)
        {
          error_class: error.class.name, severity:,
          message: ContextFilter.filter_message(error.message),
          first_backtrace_line: Fingerprint.first_app_frame(error),
          controller_action: extract_controller_action(env, context),
          job_class: extract_job_class(context),
          first_seen_at: now, last_seen_at: now,
          total_occurrences: 1, created_at: now, updated_at: now
        }
      end

      def occurrence_attributes(error, env:, context:)
        {
          backtrace: ContextFilter.filter_backtrace(error.backtrace),
          exception_chain: build_exception_chain(error),
          request_context: build_request_context(env),
          user_context: build_user_context(env),
          custom_context: ContextFilter.filter(build_custom_context(error)),
          environment_context: build_environment_context,
          breadcrumbs: BreadcrumbBuffer.current.flush,
          git_sha: RailsInformant.current_git_sha
        }
      end

      def build_custom_context(error)
        ctx = RailsInformant::Current.custom_context || {}
        ctx = ctx.merge(error.to_informant_context) if error.respond_to?(:to_informant_context)
        ctx.presence
      end

      def extract_controller_action(env, context)
        if env
          params = env["action_dispatch.request.parameters"]
          "#{params["controller"]}##{params["action"]}" if params&.key?("controller") && params&.key?("action")
        else
          case context
          in { controller: String => controller, action: String => action }
            "#{controller}##{action}"
          else
            nil
          end
        end
      end

      def extract_job_class(context)
        context.dig(:job, :class) || context[:job_class]
      end

      def filtered_url(url)
        uri = URI.parse(url)
        if uri.query.present?
          params = Rack::Utils.parse_query(uri.query)
          filtered = ContextFilter.filter(params)
          uri.query = Rack::Utils.build_query(filtered)
        end
        uri.to_s
      rescue URI::InvalidURIError
        url.split("?").first
      end

      private

      def detect_current_user(env)
        if defined?(::Current) && ::Current.respond_to?(:user) && ::Current.user
          user_context ::Current.user
        elsif env && env["warden"]&.user
          user_context env["warden"].user
        end
      end

      def extract_headers(request)
        request.headers.filter_map { |key, value|
          next unless key.start_with?("HTTP_")
          next if SKIP_HEADERS.include?(key)
          [ key.delete_prefix("HTTP_").split("_").map(&:capitalize).join("-"), value ]
        }.to_h
      end

      def user_context(user)
        return nil unless user

        ctx = { id: user.id, class: user.class.name }
        ctx[:email] = user.email if RailsInformant.capture_user_email && user.respond_to?(:email)
        ctx
      end
    end
  end
end
