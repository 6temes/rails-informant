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
        return unless RailsInformant.initialized?
        return if self_caused_error?(error)

        now = Time.current
        attrs = ContextBuilder.group_attributes(error, severity:, context:, env:, now:)
        fingerprint = Fingerprint.generate(error)

        event = run_before_record_callbacks(error, attrs, env:, fingerprint:)
        return if event.halted?

        fingerprint = event.fingerprint
        attrs[:severity] = event.severity if %w[error warning info].include?(event.severity)

        group = ErrorGroup.find_or_create_for(fingerprint, attrs)
        group.detect_regression!

        return if spike_limit_exceeded?(group)

        store_occurrence(group, error, env:, context:) if should_store_occurrence?(group)
        notify(group)
      rescue StandardError => e
        Rails.logger.error "[RailsInformant] Capture failed: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
      end

      private

      def run_before_record_callbacks(error, attrs, env:, fingerprint:)
        event = Event.new(error, attrs, env:, fingerprint:)
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
      # Primary: CurrentAttributes flag set during notification delivery.
      # Fallback: backtrace heuristic for cross-execution scenarios (e.g. queue retries).
      def self_caused_error?(error)
        Current.delivering_notification || error.backtrace&.any? { it.include?("rails_informant/notifiers") }
      end

      def should_store_occurrence?(group)
        return true if group.total_occurrences <= 1
        return true unless group.last_occurrence_stored_at
        group.last_occurrence_stored_at.before?(OCCURRENCE_COOLDOWN.seconds.ago)
      end

      def store_occurrence(group, error, env:, context:)
        now = Time.current
        ErrorGroup.transaction do
          group.occurrences.create! ContextBuilder.occurrence_attributes(error, env:, context:)
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
