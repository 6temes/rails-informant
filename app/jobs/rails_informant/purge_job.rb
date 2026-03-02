module RailsInformant
  class PurgeJob < ApplicationJob
    queue_as :default

    def perform
      return unless RailsInformant.retention_days

      cutoff = RailsInformant.retention_days.days.ago

      # IDs referenced as duplicate targets must be kept
      duplicate_target_ids = ErrorGroup.where(status: "duplicate")
        .where.not(duplicate_of_id: nil)
        .distinct
        .pluck(:duplicate_of_id)

      purgeable = ErrorGroup.where(status: "resolved")
        .where(resolved_at: ...cutoff)
        .where.not(id: duplicate_target_ids)

      purgeable.find_each do |group|
        group.destroy!
      end
    end
  end
end
