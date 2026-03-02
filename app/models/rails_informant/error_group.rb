module RailsInformant
  class ErrorGroup < ApplicationRecord
    self.table_name = "informant_error_groups"

    VALID_TRANSITIONS = {
      "duplicate" => %w[unresolved],
      "fix_pending" => %w[resolved unresolved],
      "ignored" => %w[unresolved],
      "resolved" => %w[unresolved],
      "unresolved" => %w[duplicate fix_pending ignored resolved]
    }.freeze

    has_many :occurrences, foreign_key: :error_group_id, dependent: :delete_all
    belongs_to :duplicate_of, class_name: "RailsInformant::ErrorGroup", optional: true

    validates :fingerprint, presence: true, uniqueness: true
    validates :error_class, presence: true
    validates :status, inclusion: { in: VALID_TRANSITIONS.keys }
    validate :status_transition_valid, if: :status_changed?

    scope :active, -> { where.not(status: "duplicate") }

    def regression!
      update! status: "unresolved",
        resolved_at: nil,
        fix_deployed_at: nil,
        fix_sha: nil,
        original_sha: nil,
        fix_pr_url: nil
    end

    private

    def status_transition_valid
      return if new_record?

      allowed = VALID_TRANSITIONS[status_was]
      return if allowed&.include?(status)

      errors.add :status, "cannot transition from #{status_was} to #{status}"
    end
  end
end
