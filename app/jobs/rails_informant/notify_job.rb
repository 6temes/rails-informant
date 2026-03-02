module RailsInformant
  class NotifyJob < ApplicationJob
    queue_as :default

    retry_on Net::OpenTimeout, Net::ReadTimeout, SocketError, attempts: 5, wait: 15.seconds

    def perform(error_group_id)
      group = ErrorGroup.find_by(id: error_group_id)
      return unless group

      occurrence = group.occurrences.order(created_at: :desc).first
      failures = []

      notifiers.each do |notifier|
        next unless notifier.should_notify?(group)

        notifier.notify(group, occurrence)
        group.update_column(:last_notified_at, Time.current)
      rescue => e
        failures << e
      end

      if failures.any?
        failures.drop(1).each { |e| Rails.logger.error "[RailsInformant] Notifier failed: #{e.class}: #{e.message}" }
        raise failures.first
      end
    end

    private

    def notifiers
      [].tap do |list|
        list << Notifiers::Devin.new if RailsInformant.devin_api_key.present? && RailsInformant.devin_playbook_id.present?
        list << Notifiers::Slack.new if RailsInformant.slack_webhook_url.present?
        list << Notifiers::Webhook.new if RailsInformant.webhook_url.present?
      end
    end
  end
end
