module RailsInformant
  class ErrorRecorder
    class << self
      def record(error, severity: "error", context: {}, source: nil, env: nil)
        return unless RailsInformant.initialized?

        severity = resolve_severity(error, severity)
        context = run_before_capture(error, context)
        return unless context

        fingerprint = Fingerprint.generate(error, context:)
        now = Time.current

        group = find_or_create_group fingerprint, {
          error_class: error.class.name,
          message: ContextFilter.filter_message(error.message),
          severity:,
          first_backtrace_line: Fingerprint.first_app_frame(error),
          controller_action: extract_controller_action(env, context),
          job_class: extract_job_class(context),
          first_seen_at: now,
          last_seen_at: now,
          total_occurrences: 1,
          created_at: now,
          updated_at: now
        }

        handle_regression(group)
        store_occurrence(group, error, env:, context:) if should_store_occurrence?(group)
        notify(group)
      rescue StandardError => e
        Rails.logger.error "[RailsInformant] Capture failed: #{e.class}: #{e.message}"
      end

      private

      def resolve_severity(error, default)
        RailsInformant.exception_level_filters[error.class.name] || default
      end

      def run_before_capture(error, context)
        return context unless RailsInformant.before_capture
        RailsInformant.before_capture.call(error, context)
      end

      def find_or_create_group(fingerprint, attributes)
        now = attributes[:last_seen_at]

        group = ErrorGroup.find_by(fingerprint:)
        if group
          increment_group(group, now)
        else
          group = ErrorGroup.create!(attributes.merge(fingerprint:))
        end

        group
      rescue ActiveRecord::RecordNotUnique
        # Lost race — another process created it first
        group = ErrorGroup.find_by!(fingerprint:)
        increment_group(group, attributes[:last_seen_at])
        group
      end

      def increment_group(group, timestamp)
        ErrorGroup.where(id: group.id).update_all(
          [ "total_occurrences = total_occurrences + 1, last_seen_at = ?, updated_at = ?",
           timestamp, timestamp ]
        )
        group.total_occurrences += 1
        group.last_seen_at = timestamp
      end

      def handle_regression(group)
        return unless group.status == "resolved"

        group.regression!
      end

      def should_store_occurrence?(group)
        return true if group.total_occurrences <= 1

        last_stored = group.occurrences.maximum(:created_at)
        return true unless last_stored

        last_stored.before?(RailsInformant.config.occurrence_cooldown.seconds.ago)
      rescue ActiveRecord::StatementInvalid
        true
      end

      def store_occurrence(group, error, env:, context:)
        ErrorGroup.transaction do
          group.occurrences.create!(
            backtrace: ContextFilter.filter_backtrace(error.backtrace),
            exception_chain: build_exception_chain(error),
            request_context: build_request_context(env),
            user_context: build_user_context(env),
            custom_context: ContextFilter.filter(RailsInformant::Current.custom_context),
            environment_context: build_environment_context,
            breadcrumbs: BreadcrumbBuffer.current.flush,
            git_sha: RailsInformant.current_git_sha
          )

          trim_occurrences(group)
        end
      end

      def trim_occurrences(group)
        excess = group.occurrences
          .order(created_at: :desc)
          .offset(RailsInformant.max_occurrences_per_group)
          .pluck(:id)
        Occurrence.where(id: excess).delete_all if excess.any?
      end

      def notify(group)
        return unless defined?(RailsInformant::NotifyJob)
        RailsInformant::NotifyJob.perform_later group.id
      rescue => e
        Rails.logger.error "[RailsInformant] Notification enqueue failed: #{e.message}"
      end

      def build_exception_chain(error)
        chain = []
        current = error.cause
        depth = 0

        while current && depth < RailsInformant.max_cause_depth
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
          url: request.original_url,
          method: request.request_method,
          params: request.filtered_parameters,
          headers: extract_headers(request),
          ip: request.remote_ip,
          session: {}
        }

        ContextFilter.filter(ctx)
      rescue ActionDispatch::Http::Parameters::ParseError, Rack::QueryParser::InvalidParameterError
        nil
      end

      def build_user_context(env)
        ctx = RailsInformant::Current.user_context || detect_current_user(env)
        ContextFilter.filter(ctx)
      end

      def detect_current_user(env)
        if defined?(Current) && Current.respond_to?(:user) && Current.user
          user_context Current.user
        elsif env && env["warden"]&.user
          user_context env["warden"].user
        elsif RailsInformant.current_user_method
          user_context RailsInformant.current_user_method.call
        end
      rescue NoMethodError
        nil
      end

      def user_context(user)
        return nil unless user

        { id: user.id, class: user.class.name }
      end

      def build_environment_context
        {
          rails_env: Rails.env.to_s,
          ruby_version: RUBY_VERSION,
          rails_version: Rails::VERSION::STRING,
          hostname: Socket.gethostname,
          pid: Process.pid
        }
      end

      def extract_headers(request)
        headers = {}
        request.headers.each do |key, value|
          next unless key.start_with?("HTTP_")
          next if key.in?(%w[HTTP_COOKIE HTTP_AUTHORIZATION])
          header_name = key.delete_prefix("HTTP_").split("_").map(&:capitalize).join("-")
          headers[header_name] = value
        end
        headers
      end

      def extract_controller_action(env, context)
        if env
          params = env["action_dispatch.request.parameters"]
          "#{params["controller"]}##{params["action"]}" if params&.key?("controller")
        elsif context[:controller] && context[:action]
          "#{context[:controller]}##{context[:action]}"
        end
      rescue TypeError, NoMethodError
        nil
      end

      def extract_job_class(context)
        context.dig(:job, :class) || context[:job_class]
      rescue TypeError, NoMethodError
        nil
      end
    end
  end
end
