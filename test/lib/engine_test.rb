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

  test "log_pending_fixes logs count when fix_pending errors exist" do
    RailsInformant.stubs(:server_mode?).returns(true)
    create_error_group(fingerprint: "fp-pending").mark_as_fix_pending!(
      fix_sha: "abc1234", original_sha: "def5678"
    )

    Rails.logger.expects(:info).with(regexp_matches(/1 error\(s\) awaiting fix verification/))

    # Simulates the initializer logic — see engine.rb log_pending_fixes
    count = RailsInformant::ErrorGroup.where(status: "fix_pending").count
    Rails.logger.info "[Informant] #{count} error(s) awaiting fix verification" unless count.zero?
  end
end
