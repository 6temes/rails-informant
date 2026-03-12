module RailsInformant
  class ErrorGroup < ApplicationRecord
    self.table_name = "informant_error_groups"

    API_FIELDS = %i[
      controller_action
      created_at
      duplicate_of_id
      error_class
      fingerprint
      first_backtrace_line
      first_seen_at
      fix_deployed_at
      fix_pr_url
      fix_sha
      id
      job_class
      last_seen_at
      message
      original_sha
      resolved_at
      severity
      status
      total_occurrences
      updated_at
    ].freeze

    API_DETAIL_FIELDS = (API_FIELDS + %i[
      last_notified_at
      last_occurrence_stored_at
      notes
    ]).freeze

    VALID_TRANSITIONS = {
      "duplicate" => %w[unresolved],
      "fix_pending" => %w[resolved unresolved],
      "ignored" => %w[unresolved],
      "resolved" => %w[unresolved],
      "unresolved" => %w[duplicate fix_pending ignored resolved]
    }.freeze

    has_many :occurrences, foreign_key: :error_group_id, inverse_of: :error_group, dependent: :delete_all
    belongs_to :duplicate_of, class_name: "RailsInformant::ErrorGroup", optional: true

    before_save :set_resolved_at, if: :status_changed?

    validates :error_class, presence: true
    validates :fingerprint, presence: true, uniqueness: true
    validates :notes, length: { maximum: 10_000 }, allow_nil: true
    validates :severity, inclusion: { in: %w[error warning info] }
    validates :status, inclusion: { in: VALID_TRANSITIONS.keys }
    validate :status_transition_valid, if: :status_changed?

    scope :active, -> { where.not(status: "duplicate") }
    scope :before, ->(time) { where(last_seen_at: ..time) if time }
    scope :by_controller_action, ->(action) { where(controller_action: action) if action }
    scope :by_error_class, ->(error_class) { where(error_class:) if error_class }
    scope :by_job_class, ->(job_class) { where(job_class:) if job_class }
    scope :by_severity, ->(severity) { where(severity:) if severity }
    scope :by_status, ->(status) { where(status:) if status }
    scope :search, ->(q) { where(arel_table[:message].matches("%#{sanitize_sql_like(q)}%")) if q }
    scope :since, ->(time) { where(last_seen_at: time..) if time }

    class << self
      def find_or_create_for(fingerprint, attributes)
        now = attributes[:last_seen_at]
        if (group = find_by(fingerprint:))
          increment_counters group, now
        else
          group = create!(attributes.merge(fingerprint:))
        end
        group
      rescue ActiveRecord::RecordNotUnique
        group = find_by!(fingerprint:)
        increment_counters group, now
        group
      end

      private

      def increment_counters(group, timestamp)
        where(id: group.id).update_all(
          [ "total_occurrences = total_occurrences + 1, last_seen_at = ?, updated_at = ?", timestamp, timestamp ]
        )
        group.total_occurrences += 1
        group.last_seen_at = timestamp
      end
    end

    MAX_DUPLICATE_CHAIN_DEPTH = 10

    def self.circular_duplicate_chain?(target_id, source_id)
      return false unless source_id

      seen = Set.new([ target_id ])
      current_id = source_id

      MAX_DUPLICATE_CHAIN_DEPTH.times do
        return false unless current_id
        return true if seen.include?(current_id)
        seen << current_id
        current_id = where(id: current_id).pick(:duplicate_of_id)
      end

      true # depth exceeded, treat as circular
    end

    def circular_duplicate_chain?(original_id)
      self.class.circular_duplicate_chain?(original_id, duplicate_of_id)
    end

    def mark_as_fix_pending!(fix_sha:, original_sha:, fix_pr_url: nil)
      raise RailsInformant::InvalidParameterError, "fix_sha is required" unless fix_sha.present?
      raise RailsInformant::InvalidParameterError, "original_sha is required" unless original_sha.present?
      validate_sha_format! fix_sha
      validate_sha_format! original_sha
      validate_url_scheme! fix_pr_url if fix_pr_url.present?

      update!(status: "fix_pending", fix_sha:, original_sha:, fix_pr_url:)
    end

    def mark_as_duplicate_of!(target_id)
      raise RailsInformant::InvalidParameterError, "duplicate_of_id is required" unless target_id.present?

      target = self.class.find_by(id: target_id)
      raise RailsInformant::InvalidParameterError, "Target error group not found" unless target
      raise RailsInformant::InvalidParameterError, "Cannot mark as duplicate of itself" if target.id == id
      raise RailsInformant::InvalidParameterError, "Circular duplicate chain detected" if target.circular_duplicate_chain?(id)

      update!(status: "duplicate", duplicate_of: target)
    end

    def detect_regression!
      return unless status == "resolved"

      changed = self.class.where(id:, status: "resolved").update_all(
        status: "unresolved", resolved_at: nil, fix_deployed_at: nil,
        fix_sha: nil, original_sha: nil, fix_pr_url: nil, updated_at: Time.current)
      return unless changed > 0

      assign_attributes status: "unresolved", resolved_at: nil, fix_deployed_at: nil,
        fix_sha: nil, original_sha: nil, fix_pr_url: nil
    end

    private

    def validate_sha_format!(sha)
      unless sha&.match?(RailsInformant::SHA_FORMAT)
        raise RailsInformant::InvalidParameterError, "Invalid SHA format"
      end
    end

    def validate_url_scheme!(url)
      uri = URI.parse(url)
      unless uri.scheme == "https"
        raise RailsInformant::InvalidParameterError, "Only HTTPS URLs are allowed"
      end
    rescue URI::InvalidURIError
      raise RailsInformant::InvalidParameterError, "Invalid URL"
    end

    def set_resolved_at
      self.resolved_at = status == "resolved" ? Time.current : nil
    end

    def status_transition_valid
      return if new_record?

      allowed = VALID_TRANSITIONS[status_was]
      return if allowed&.include?(status)

      errors.add :status, "cannot transition from #{status_was} to #{status}"
    end
  end
end
