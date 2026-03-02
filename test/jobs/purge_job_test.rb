require "test_helper"

class RailsInformant::PurgeJobTest < ActiveJob::TestCase
  setup do
    @old_retention = RailsInformant.config.retention_days
  end

  teardown do
    RailsInformant.config.retention_days = @old_retention
  end

  test "does nothing when retention_days is nil" do
    RailsInformant.config.retention_days = nil

    group = create_resolved_group(resolved_at: 1.year.ago)

    RailsInformant::PurgeJob.perform_now

    assert RailsInformant::ErrorGroup.exists?(group.id)
  end

  test "purges resolved errors older than retention_days" do
    RailsInformant.config.retention_days = 30

    old_group = create_resolved_group(resolved_at: 31.days.ago)
    old_group.occurrences.create!(backtrace: [ "/app/foo.rb:1" ])

    recent_group = create_resolved_group(resolved_at: 1.day.ago, fingerprint: "recent")

    RailsInformant::PurgeJob.perform_now

    assert_not RailsInformant::ErrorGroup.exists?(old_group.id)
    assert RailsInformant::ErrorGroup.exists?(recent_group.id)
  end

  test "does not purge unresolved errors" do
    RailsInformant.config.retention_days = 1

    group = RailsInformant::ErrorGroup.create!(
      fingerprint: "unresolved-fp",
      error_class: "StandardError",
      message: "test",
      status: "unresolved",
      first_seen_at: 1.year.ago,
      last_seen_at: 1.year.ago
    )

    RailsInformant::PurgeJob.perform_now

    assert RailsInformant::ErrorGroup.exists?(group.id)
  end

  test "preserves duplicate targets" do
    RailsInformant.config.retention_days = 1

    target = create_resolved_group(resolved_at: 1.year.ago, fingerprint: "target-fp")

    RailsInformant::ErrorGroup.create!(
      fingerprint: "dup-fp",
      error_class: "StandardError",
      message: "test",
      status: "duplicate",
      duplicate_of: target,
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )

    RailsInformant::PurgeJob.perform_now

    assert RailsInformant::ErrorGroup.exists?(target.id), "Duplicate target should not be purged"
  end

  private

  def create_resolved_group(resolved_at:, fingerprint: SecureRandom.hex(8))
    RailsInformant::ErrorGroup.create!(
      fingerprint: fingerprint,
      error_class: "StandardError",
      message: "test",
      status: "resolved",
      resolved_at: resolved_at,
      first_seen_at: 1.year.ago,
      last_seen_at: resolved_at
    )
  end
end
