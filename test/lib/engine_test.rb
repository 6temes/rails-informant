require "test_helper"

class RailsInformant::EngineTest < ActiveSupport::TestCase
  test "validate_api_token! raises in server mode when api_token is nil" do
    RailsInformant.config.capture_errors = true
    RailsInformant.config.api_token = nil
    RailsInformant.stubs(:server_mode?).returns(true)

    error = assert_raises(RuntimeError) { RailsInformant::Engine.validate_api_token! }
    assert_match(/api_token must be configured/, error.message)
  end

  test "validate_api_token! warns outside server mode when api_token is nil" do
    RailsInformant.config.capture_errors = true
    RailsInformant.config.api_token = nil
    RailsInformant.stubs(:server_mode?).returns(false)

    Rails.logger.expects(:warn).with(regexp_matches(/api_token must be configured/))
    assert_nothing_raised { RailsInformant::Engine.validate_api_token! }
  end

  test "validate_api_token! does not raise when capture_errors is disabled" do
    RailsInformant.config.capture_errors = false
    RailsInformant.config.api_token = nil

    assert_nothing_raised { RailsInformant::Engine.validate_api_token! }
  end

  test "validate_api_token! does not raise when api_token is configured" do
    RailsInformant.config.capture_errors = true
    RailsInformant.config.api_token = "test-token-00112233445566778899aabb"

    assert_nothing_raised { RailsInformant::Engine.validate_api_token! }
  end

  test "validate_api_token! raises in server mode when api_token is shorter than 32 characters" do
    RailsInformant.config.capture_errors = true
    RailsInformant.config.api_token = "short-token"
    RailsInformant.stubs(:server_mode?).returns(true)

    error = assert_raises(RuntimeError) { RailsInformant::Engine.validate_api_token! }
    assert_match(/at least 32 characters/, error.message)
    assert_match(/SecureRandom\.hex\(32\)/, error.message)
  end

  test "validate_api_token! warns outside server mode when api_token is too short" do
    RailsInformant.config.capture_errors = true
    RailsInformant.config.api_token = "short-token"
    RailsInformant.stubs(:server_mode?).returns(false)

    Rails.logger.expects(:warn).with(regexp_matches(/at least 32 characters/))
    assert_nothing_raised { RailsInformant::Engine.validate_api_token! }
  end

  test "validate_api_token! does not raise for short token when capture_errors is disabled" do
    RailsInformant.config.capture_errors = false
    RailsInformant.config.api_token = "short-token"

    assert_nothing_raised { RailsInformant::Engine.validate_api_token! }
  end

  test "detect_deploy resolves fix_pending groups with different original_sha" do
    current_sha = "abc1234abc1234abc1234abc1234abc1234abc12"
    RailsInformant.stubs(:server_mode?).returns(true)
    RailsInformant.stubs(:current_git_sha).returns(current_sha)

    should_resolve = create_error_group(fingerprint: "fp-resolve")
    should_resolve.mark_as_fix_pending! fix_sha: "def5678def5678def5678def5678def5678def56", original_sha: "0000000"

    should_keep = create_error_group(fingerprint: "fp-keep")
    should_keep.mark_as_fix_pending! fix_sha: "def5678def5678def5678def5678def5678def56", original_sha: current_sha

    unrelated = create_error_group(fingerprint: "fp-unrelated")

    # Simulate the detect_deploy initializer logic
    now = Time.current
    RailsInformant::ErrorGroup
      .where(status: "fix_pending")
      .where.not(original_sha: current_sha)
      .in_batches(of: 100)
      .update_all(status: "resolved", resolved_at: now, fix_deployed_at: now, updated_at: now)

    should_resolve.reload
    assert_equal "resolved", should_resolve.status
    assert_not_nil should_resolve.resolved_at
    assert_not_nil should_resolve.fix_deployed_at

    should_keep.reload
    assert_equal "fix_pending", should_keep.status

    unrelated.reload
    assert_equal "unresolved", unrelated.status
  end
end
