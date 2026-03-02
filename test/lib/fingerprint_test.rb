require "test_helper"

class RailsInformant::FingerprintTest < ActiveSupport::TestCase
  test "generates deterministic fingerprint" do
    error = build_error("/app/models/user.rb:42:in `save'")
    fp1 = RailsInformant::Fingerprint.generate(error)
    fp2 = RailsInformant::Fingerprint.generate(error)
    assert_equal fp1, fp2
  end

  test "normalizes line numbers" do
    error1 = build_error("/app/models/user.rb:42:in `save'")
    error2 = build_error("/app/models/user.rb:99:in `save'")
    assert_equal(
      RailsInformant::Fingerprint.generate(error1),
      RailsInformant::Fingerprint.generate(error2)
    )
  end

  test "different classes produce different fingerprints" do
    error1 = StandardError.new("boom")
    error1.set_backtrace [ "/app/models/user.rb:42" ]
    error2 = RuntimeError.new("boom")
    error2.set_backtrace [ "/app/models/user.rb:42" ]

    assert_not_equal(
      RailsInformant::Fingerprint.generate(error1),
      RailsInformant::Fingerprint.generate(error2)
    )
  end

  test "generates fingerprint from class name when backtrace is nil" do
    error = StandardError.new("no backtrace")
    fingerprint = RailsInformant::Fingerprint.generate(error)

    assert fingerprint.present?
    assert_equal Digest::SHA256.hexdigest("StandardError"), fingerprint
  end

  test "preserves numbered directories when normalizing line numbers" do
    error1 = build_error("/app/v2/models/user.rb:42:in `save'")
    error2 = build_error("/app/v2/models/user.rb:99:in `save'")

    assert_equal(
      RailsInformant::Fingerprint.generate(error1),
      RailsInformant::Fingerprint.generate(error2)
    )

    error_different_dir = build_error("/app/v3/models/user.rb:42:in `save'")
    assert_not_equal(
      RailsInformant::Fingerprint.generate(error1),
      RailsInformant::Fingerprint.generate(error_different_dir)
    )
  end

  test "skips gem frames for first app frame" do
    error = StandardError.new("boom")
    error.set_backtrace [
      "/gems/activesupport-8.1.0/lib/foo.rb:10",
      "/app/models/user.rb:42:in `save'"
    ]

    frame = RailsInformant::Fingerprint.first_app_frame(error)
    assert_equal "/app/models/user.rb:42:in `save'", frame
  end

  private

  def build_error(frame)
    error = StandardError.new("boom")
    error.set_backtrace [ frame ]
    error
  end
end
