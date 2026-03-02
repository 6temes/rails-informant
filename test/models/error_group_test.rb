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
      group.resolved_at = Time.current if target == "resolved"
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

  test "regression clears temporal fields" do
    group = create_error_group
    group.update_columns status: "resolved", resolved_at: Time.current,
      fix_sha: "abc", original_sha: "def", fix_pr_url: "http://example.com"

    group.reload
    group.regression!
    group.reload

    assert_equal "unresolved", group.status
    assert_nil group.resolved_at
    assert_nil group.fix_deployed_at
    assert_nil group.fix_sha
    assert_nil group.original_sha
    assert_nil group.fix_pr_url
  end

  test "fingerprint uniqueness" do
    create_error_group(fingerprint: "unique-fp")
    duplicate = build_error_group(fingerprint: "unique-fp")
    assert_not duplicate.valid?
  end

  private

  def create_error_group(fingerprint: SecureRandom.hex(8), status: "unresolved", **attrs)
    RailsInformant::ErrorGroup.create!(
      fingerprint:,
      error_class: "StandardError",
      message: "test error",
      status:,
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      **attrs
    )
  end

  def build_error_group(fingerprint: SecureRandom.hex(8), **attrs)
    RailsInformant::ErrorGroup.new(
      fingerprint:,
      error_class: "StandardError",
      message: "test error",
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      **attrs
    )
  end
end
