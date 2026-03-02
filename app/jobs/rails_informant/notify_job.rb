module RailsInformant
  class NotifyJob < ApplicationJob
    queue_as :default

    retry_on ::Net::OpenTimeout, ::Net::ReadTimeout, ::SocketError, RailsInformant::NotifierError, attempts: 5, wait: 15.seconds
    discard_on ActiveRecord::RecordNotFound

    def perform(group)
      occurrence = group.occurrences.order(created_at: :desc).first
      failures = []

      notifiers.each do |notifier|
        next unless notifier.should_notify?(group)

        notifier.notify(group, occurrence)
      rescue StandardError => e
        failures << e
      end

      group.update_column(:last_notified_at, Time.current) if failures.empty?

      if failures.any?
        failures.drop(1).each { |e| Rails.logger.error "[RailsInformant] Notifier failed: #{e.class}: #{e.message}" }
        raise failures.first
      end
    end

    private

    def notifiers
      RailsInformant.config.notifiers
    end
  end
end
