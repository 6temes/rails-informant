module RailsInformant
  module Notifiers
    class CircuitBreaker
      FAILURE_THRESHOLD = 5
      RESET_TIMEOUT = 10.minutes

      class << self
        def open?
          return false if failure_count < FAILURE_THRESHOLD

          last_failure_at > RESET_TIMEOUT.ago
        end

        def record_failure
          @failure_count = failure_count + 1
          @last_failure_at = Time.current
        end

        def record_success
          reset!
        end

        def reset!
          @failure_count = 0
          @last_failure_at = nil
        end

        private

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
