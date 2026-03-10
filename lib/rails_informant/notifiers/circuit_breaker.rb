module RailsInformant
  module Notifiers
    class CircuitBreaker
      FAILURE_THRESHOLD = 5
      RESET_TIMEOUT = 10.minutes
      MUTEX = Mutex.new
      private_constant :MUTEX

      class << self
        def open?
          MUTEX.synchronize do
            return false if failure_count < FAILURE_THRESHOLD
            last_failure_at > RESET_TIMEOUT.ago
          end
        end

        def record_failure
          MUTEX.synchronize do
            @failure_count = failure_count + 1
            @last_failure_at = Time.current
          end
        end

        def record_success
          MUTEX.synchronize { _reset! }
        end

        def reset!
          MUTEX.synchronize { _reset! }
        end

        private

        def _reset!
          @failure_count = 0
          @last_failure_at = nil
        end

        def failure_count
          @failure_count || 0
        end

        def last_failure_at
          @last_failure_at || Time.at(0)
        end
      end
    end
  end
end
