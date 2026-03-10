module RailsInformant
  class NotifyJob < ApplicationJob
    queue_as :default

    retry_on ::Net::OpenTimeout, ::Net::ReadTimeout, ::SocketError, RailsInformant::NotifierError, attempts: 5, wait: 15.seconds
    discard_on ActiveRecord::RecordNotFound,
               ArgumentError,
               Errno::ECONNREFUSED,
               Errno::ECONNRESET,
               Errno::EHOSTUNREACH,
               OpenSSL::SSL::SSLError

    def perform(group)
      Current.delivering_notification = true

      occurrence = group.occurrences.order(created_at: :desc).first
      failures = []

      notifiers.each do |notifier|
        next unless notifier.should_notify?(group)

        notifier.notify(group, occurrence)
      rescue StandardError => e
        failures << e
      end

      if failures.empty?
        group.update_column(:last_notified_at, Time.current)
        Notifiers::CircuitBreaker.record_success
      else
        Notifiers::CircuitBreaker.record_failure
        failures.drop(1).each { |e| Rails.logger.error "[RailsInformant] Notifier failed: #{e.class}: #{e.message}" }
        raise failures.first
      end
    ensure
      Current.delivering_notification = false
    end

    private

    def notifiers
      RailsInformant.config.notifiers
    end
  end
end
