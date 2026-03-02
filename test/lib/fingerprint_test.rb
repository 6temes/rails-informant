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

  test "skips gem frames for first app frame" do
    error = StandardError.new("boom")
    error.set_backtrace [
      "/gems/activesupport-8.1.0/lib/foo.rb:10",
      "/app/models/user.rb:42:in `save'"
    ]

    frame = RailsInformant::Fingerprint.first_app_frame(error)
    assert_equal "/app/models/user.rb:42:in `save'", frame
  end

  test "custom fingerprint overrides default" do
    RailsInformant.config.custom_fingerprint = ->(_error, _context) { "custom-fp" }

    error = build_error("/app/models/user.rb:42")
    assert_equal "custom-fp", RailsInformant::Fingerprint.generate(error)
  end

  test "custom fingerprint returning nil falls through to default" do
    RailsInformant.config.custom_fingerprint = ->(_error, _context) { nil }

    error = build_error("/app/models/user.rb:42")
    fp = RailsInformant::Fingerprint.generate(error)
    assert fp.present?
    assert_not_equal "nil", fp
  end

  private

  def build_error(frame)
    error = StandardError.new("boom")
    error.set_backtrace [ frame ]
    error
  end
end
