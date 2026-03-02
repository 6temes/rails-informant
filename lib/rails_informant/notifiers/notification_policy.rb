module RailsInformant
  module Notifiers
    module NotificationPolicy
      MILESTONE_COUNTS = [ 10, 100, 1000 ].freeze

      def should_notify?(error_group)
        return true if error_group.total_occurrences == 1
        return true if error_group.total_occurrences.in?(MILESTONE_COUNTS)
        return true if error_group.last_notified_at.nil?
        return true if error_group.last_notified_at < RailsInformant.notification_cooldown.seconds.ago

        false
      end
    end
  end
end
