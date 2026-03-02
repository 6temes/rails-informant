require "test_helper"

class RailsInformant::ErrorGroupTest < ActiveSupport::TestCase
  test "valid statuses" do
    group = create_error_group
    assert group.valid?
    assert_equal "unresolved", group.status
  end

  test "invalid status rejected" do
    group = create_error_group
    group.status = "bogus"
    assert_not group.valid?
  end

  test "valid transitions from unresolved" do
    %w[duplicate fix_pending ignored resolved].each do |target|
      group = create_error_group(fingerprint: "fp-#{target}")
      group.status = target
      group.duplicate_of = create_error_group(fingerprint: "dup-target-#{target}") if target == "duplicate"
      assert group.valid?, "Expected transition unresolved -> #{target} to be valid"
    end
  end

  test "invalid transition from resolved to ignored" do
    group = create_error_group(status: "unresolved")
    group.update_column :status, "resolved"
    group.reload
    group.status = "ignored"
    assert_not group.valid?
  end

  test "sets resolved_at when transitioning to resolved" do
    group = create_error_group
    assert_nil group.resolved_at

    group.update! status: "resolved"
    assert_not_nil group.resolved_at
  end

  test "clears resolved_at when transitioning away from resolved" do
    group = create_error_group
    group.update! status: "resolved"
    assert_not_nil group.resolved_at

    group.update! status: "unresolved"
    assert_nil group.resolved_at
  end

  test "notes within length limit are valid" do
    group = create_error_group(notes: "a" * 10_000)
    assert group.valid?
  end

  test "notes exceeding length limit are invalid" do
    group = create_error_group
    group.notes = "a" * 10_001
    assert_not group.valid?
    assert group.errors[:notes].any?
  end

  test "nil notes are valid" do
    group = create_error_group(notes: nil)
    assert group.valid?
  end

  test "fingerprint uniqueness" do
    create_error_group(fingerprint: "unique-fp")
    duplicate = build_error_group(fingerprint: "unique-fp")
    assert_not duplicate.valid?
  end

  # circular_duplicate_chain? (class method)

  test "detects circular duplicate chain" do
    a = create_error_group
    b = create_error_group
    c = create_error_group

    b.update_columns duplicate_of_id: a.id, status: "duplicate"
    c.update_columns duplicate_of_id: b.id, status: "duplicate"

    assert RailsInformant::ErrorGroup.circular_duplicate_chain?(a.id, c.id)
  end

  test "returns false for non-circular chain" do
    a = create_error_group
    b = create_error_group
    b.update_columns duplicate_of_id: a.id, status: "duplicate"
    c = create_error_group

    assert_not RailsInformant::ErrorGroup.circular_duplicate_chain?(c.id, b.id)
  end

  test "returns false when no duplicate_of_id" do
    a = create_error_group
    assert_not RailsInformant::ErrorGroup.circular_duplicate_chain?(a.id, nil)
  end

  # mark_as_fix_pending!

  test "mark_as_fix_pending! updates status and fix metadata" do
    group = create_error_group
    group.mark_as_fix_pending! fix_sha: "abc1234", original_sha: "def4567", fix_pr_url: "https://github.com/pr/1"

    group.reload
    assert_equal "fix_pending", group.status
    assert_equal "abc1234", group.fix_sha
    assert_equal "def4567", group.original_sha
    assert_equal "https://github.com/pr/1", group.fix_pr_url
  end

  test "mark_as_fix_pending! raises on missing fix_sha" do
    group = create_error_group
    error = assert_raises(RailsInformant::InvalidParameterError) { group.mark_as_fix_pending! fix_sha: nil, original_sha: "def4567" }
    assert_equal "fix_sha is required", error.message
  end

  test "mark_as_fix_pending! raises on missing original_sha" do
    group = create_error_group
    error = assert_raises(RailsInformant::InvalidParameterError) { group.mark_as_fix_pending! fix_sha: "abc1234", original_sha: nil }
    assert_equal "original_sha is required", error.message
  end

  test "mark_as_fix_pending! raises on invalid SHA format" do
    group = create_error_group
    assert_raises(RailsInformant::InvalidParameterError) { group.mark_as_fix_pending! fix_sha: "not-valid!", original_sha: "def4567" }
  end

  test "mark_as_fix_pending! raises on non-HTTPS URL" do
    group = create_error_group
    assert_raises(RailsInformant::InvalidParameterError) { group.mark_as_fix_pending! fix_sha: "abc1234", original_sha: "def4567", fix_pr_url: "http://example.com" }
  end

  # mark_as_duplicate_of!

  test "mark_as_duplicate_of! updates status and duplicate reference" do
    group = create_error_group
    target = create_error_group
    group.mark_as_duplicate_of! target.id

    group.reload
    assert_equal "duplicate", group.status
    assert_equal target.id, group.duplicate_of_id
  end

  test "mark_as_duplicate_of! raises on self-reference" do
    group = create_error_group
    assert_raises(RailsInformant::InvalidParameterError, "Cannot mark as duplicate of itself") { group.mark_as_duplicate_of! group.id }
  end

  test "mark_as_duplicate_of! raises on missing target" do
    group = create_error_group
    assert_raises(RailsInformant::InvalidParameterError) { group.mark_as_duplicate_of! 999_999 }
  end

  test "mark_as_duplicate_of! raises on circular chain" do
    a = create_error_group
    b = create_error_group
    b.update_columns duplicate_of_id: a.id, status: "duplicate"

    assert_raises(RailsInformant::InvalidParameterError, "Circular duplicate chain detected") { a.mark_as_duplicate_of! b.id }
  end

  # find_or_create_for

  test "find_or_create_for creates a new group when fingerprint is new" do
    now = Time.current
    attrs = group_attributes(now:)

    assert_difference -> { RailsInformant::ErrorGroup.count }, 1 do
      group = RailsInformant::ErrorGroup.find_or_create_for("new-fp", attrs)
      assert_equal "new-fp", group.fingerprint
      assert_equal "StandardError", group.error_class
      assert_equal 1, group.total_occurrences
    end
  end

  test "find_or_create_for increments counter for existing fingerprint" do
    now = Time.current
    attrs = group_attributes(now:)
    existing = RailsInformant::ErrorGroup.create!(attrs.merge(fingerprint: "existing-fp"))

    assert_no_difference -> { RailsInformant::ErrorGroup.count } do
      group = RailsInformant::ErrorGroup.find_or_create_for("existing-fp", attrs)
      assert_equal existing.id, group.id
      assert_equal 2, group.total_occurrences
    end

    existing.reload
    assert_equal 2, existing.total_occurrences
  end

  test "find_or_create_for handles race condition via RecordNotUnique" do
    now = Time.current
    attrs = group_attributes(now:)

    # Create the group that will be "found" after the race condition
    race_winner = create_error_group(fingerprint: "race-fp")

    # Simulate race: find_by returns nil, create! raises RecordNotUnique,
    # then find_by! finds the record created by the other process
    RailsInformant::ErrorGroup.stubs(:find_by).returns(nil)
    RailsInformant::ErrorGroup.stubs(:create!).raises(ActiveRecord::RecordNotUnique)
    RailsInformant::ErrorGroup.stubs(:find_by!).returns(race_winner)

    group = RailsInformant::ErrorGroup.find_or_create_for("race-fp", attrs)
    assert_equal race_winner.id, group.id
  end

  # detect_regression!

  test "detect_regression! reopens resolved group and clears fix fields" do
    group = create_error_group
    group.update_columns status: "resolved", resolved_at: Time.current,
      fix_deployed_at: Time.current, fix_sha: "abc123", original_sha: "def456",
      fix_pr_url: "https://github.com/org/repo/pull/1"

    group.reload
    group.detect_regression!

    assert_equal "unresolved", group.status
    assert_nil group.resolved_at
    assert_nil group.fix_deployed_at
    assert_nil group.fix_sha
    assert_nil group.original_sha
    assert_nil group.fix_pr_url

    group.reload
    assert_equal "unresolved", group.status
  end

  test "detect_regression! is a no-op for unresolved group" do
    group = create_error_group(status: "unresolved")

    group.detect_regression!

    assert_equal "unresolved", group.status
  end

  test "detect_regression! is a no-op for ignored group" do
    group = create_error_group
    group.update_columns status: "ignored"
    group.reload

    group.detect_regression!

    assert_equal "ignored", group.status
  end

  private

  def group_attributes(now: Time.current)
    {
      error_class: "StandardError",
      message: "test error",
      severity: "error",
      first_seen_at: now,
      last_seen_at: now,
      total_occurrences: 1,
      created_at: now,
      updated_at: now
    }
  end
end
