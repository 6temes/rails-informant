module RailsInformant
  class PurgeJob < ApplicationJob
    queue_as :default
    retry_on ActiveRecord::InvalidForeignKey, wait: 1.second, attempts: 3

    def perform
      return unless RailsInformant.retention_days

      cutoff = RailsInformant.retention_days.days.ago

      # IDs referenced as duplicate targets must be kept (subquery avoids TOCTOU)
      duplicate_target_ids = ErrorGroup.where(status: "duplicate")
        .where.not(duplicate_of_id: nil)
        .distinct
        .select(:duplicate_of_id)

      # Split into separate queries so each can hit its composite index cleanly
      resolved_scope = ErrorGroup.where(status: "resolved").where(resolved_at: ...cutoff).where.not(id: duplicate_target_ids)
      ignored_scope = ErrorGroup.where(status: "ignored").where(updated_at: ...cutoff).where.not(id: duplicate_target_ids)

      [ ignored_scope, resolved_scope ].each do |purgeable|
        purgeable.in_batches(of: 500) do |batch|
          Occurrence.where(error_group_id: batch.select(:id)).delete_all
          batch.delete_all
        end
      end
    end
  end
end
