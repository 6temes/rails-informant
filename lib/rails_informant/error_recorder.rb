module RailsInformant
  class ErrorRecorder
    MAX_OCCURRENCES_PER_GROUP = 25
    OCCURRENCE_COOLDOWN = 5 # seconds

    @_spike_counters = {}
    @_spike_mutex = Mutex.new

    class << self
      def reset_spike_counters!
        @_spike_counters.clear
      end

      def record(error, severity: "error", context: {}, source: nil, env: nil)
        # Never capture from an interactive console — the operator sees errors
        # live, so recording and alerting on them is noise.
        return if RailsInformant.console_mode?
        # `rails runner` is the same shape when an operator drives it by hand, but it also
        # backs cron and scheduled tasks, where those errors are the whole point. Apps that
        # only use it interactively opt out; capturing stays the default.
        return if RailsInformant.runner_mode? && !RailsInformant.config.capture_runner_errors
        return unless RailsInformant.initialized?
        return if self_caused_error?(error)

        now = Time.current
        attrs = ContextBuilder.group_attributes(error, severity:, context:, env:, now:)
        fingerprint = Fingerprint.generate(error)

        event = run_before_record_callbacks(error, attrs, env:, fingerprint:)
        return if event.halted?

        attrs[:severity] = event.severity if %w[error warning info].include?(event.severity)

        record_group(event.fingerprint, attrs) { ContextBuilder.occurrence_attributes(error, env:, context:) }
      rescue StandardError => e
        log_capture_failure e
      end

      # Called by the browser ingest endpoint once per report. The ingest
      # request's own env, params and breadcrumbs describe the endpoint, not
      # the page, so none of them reach the stored group or occurrence.
      def record_browser(report, context:, base_url:, remote_ip:, user_agent:)
        return unless RailsInformant.initialized?

        browser_report = BrowserReport.new(report, context:, base_url:, remote_ip:, user_agent:)
        return if RailsInformant.ignored_request_path?(browser_report.page_path)
        return if RailsInformant.ignored_error_class?(browser_report.error_class)

        attrs = browser_report.group_attributes(now: Time.current)
        fingerprint = BrowserFingerprint.generate(error_class: attrs[:error_class], message: attrs[:message], stack: browser_report.stack)

        event = run_before_record_callbacks(browser_report.error, attrs, fingerprint:, request_path: browser_report.page_path, source: "browser")
        return if event.halted?

        attrs[:severity] = event.severity if %w[error warning info].include?(event.severity)
        return if browser_group_limit_reached?(event.fingerprint)

        record_group(event.fingerprint, attrs, rendered_at: context&.rendered_at) { browser_report.occurrence_attributes }
      rescue StandardError => e
        log_capture_failure e
      ensure
        BreadcrumbBuffer.current.flush
      end

      private

      def record_group(fingerprint, attrs, rendered_at: nil, &occurrence_attributes)
        group = ErrorGroup.find_or_create_for(fingerprint, attrs)
        stale_page = group.rendered_before_resolution?(rendered_at)
        group.detect_regression! unless stale_page

        return if spike_limit_exceeded?(group)

        store_occurrence(group, occurrence_attributes) if should_store_occurrence?(group)
        # The group stays resolved, so the notification policy would
        # otherwise alert on an error the fix already addressed.
        notify(group) unless stale_page
      end

      # A DB count rather than a process counter, so the cap holds across
      # workers and under a null cache store.
      def browser_group_limit_reached?(fingerprint)
        return false if ErrorGroup.exists?(fingerprint:)

        limit = RailsInformant.config.browser_new_group_limit
        return false if ErrorGroup.where(source: "browser", created_at: 1.hour.ago..).count < limit

        unless Current.browser_group_limit_logged
          Current.browser_group_limit_logged = true
          Rails.logger.warn "[RailsInformant] Dropped browser report: browser_new_group_limit (#{limit}) new groups already created this hour"
        end
        true
      end

      def log_capture_failure(error)
        Rails.logger.error "[RailsInformant] Capture failed: #{error.class}: #{error.message}\n#{error.backtrace&.first(5)&.join("\n")}"
      end

      def run_before_record_callbacks(error, attrs, fingerprint:, **)
        event = Event.new(error, attrs, fingerprint:, **)
        callbacks = RailsInformant.config.before_record_callbacks

        callbacks.each do |callback|
          callback.call(event)
          break if event.halted?
        rescue StandardError => e
          Rails.logger.error "[RailsInformant] before_record callback failed: #{e.class}: #{e.message}"
        end

        event
      end

      MAX_SPIKE_ENTRIES = 1_000

      def spike_limit_exceeded?(group)
        config = RailsInformant.config.spike_protection
        return false unless config

        threshold, window = config.values_at(:threshold, :window)

        @_spike_mutex.synchronize do
          prune_spike_counters!(window) if @_spike_counters.size > MAX_SPIKE_ENTRIES

          entry = @_spike_counters[group.id] ||= { count: 0, window_start: Time.current }

          if entry[:window_start] < window.ago
            entry[:count] = 1
            entry[:window_start] = Time.current
            false
          else
            entry[:count] += 1
            entry[:count] > threshold
          end
        end
      end

      def prune_spike_counters!(window)
        cutoff = window.ago
        @_spike_counters.reject! { |_, v| v[:window_start] < cutoff }
      end

      # Detect errors caused by RailsInformant itself to prevent feedback loops.
      # Primary: CurrentAttributes flags set during notification delivery and
      # browser report ingest, where a recorded failure could amplify a flood.
      # Fallback: backtrace heuristic for cross-execution scenarios (e.g. queue retries).
      def self_caused_error?(error)
        Current.delivering_notification || Current.ingesting_browser_report ||
          error.backtrace&.any? { it.include?("rails_informant/notifiers") }
      end

      def should_store_occurrence?(group)
        return true if group.total_occurrences <= 1
        return true unless group.last_occurrence_stored_at
        group.last_occurrence_stored_at.before?(OCCURRENCE_COOLDOWN.seconds.ago)
      end

      def store_occurrence(group, occurrence_attributes)
        now = Time.current
        ErrorGroup.transaction do
          group.occurrences.create! occurrence_attributes.call
          ErrorGroup.where(id: group.id).update_all last_occurrence_stored_at: now, updated_at: now
          group.last_occurrence_stored_at = now
        end
        trim_occurrences(group) if group.total_occurrences > MAX_OCCURRENCES_PER_GROUP
      end

      def trim_occurrences(group)
        keep_ids = group.occurrences.order(created_at: :desc).limit(MAX_OCCURRENCES_PER_GROUP).select(:id)
        Occurrence.where(error_group_id: group.id).where.not(id: keep_ids).delete_all
      end

      def notify(group)
        return if Notifiers::CircuitBreaker.open?
        return unless RailsInformant.config.notifiers.any? { it.should_notify?(group) }
        RailsInformant::NotifyJob.perform_later group
      end
    end
  end
end
