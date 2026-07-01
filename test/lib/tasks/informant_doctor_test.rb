require "test_helper"
require "stringio"

# Exercises the informant:doctor channel (RailsInformant::Doctor) directly: the
# rake task is a one-line wrapper that `exit`s with the code run returns.
class RailsInformant::DoctorTest < ActiveSupport::TestCase
  test "reports stale, names the fix, and exits nonzero" do
    io = StringIO.new
    code = doctor(:stale, io).run

    assert_match "OUT OF DATE", io.string
    assert_match "bin/rails g rails_informant:skill", io.string
    assert_equal 1, code
  end

  test "reports current and exits zero" do
    io = StringIO.new
    code = doctor(:current, io).run

    assert_match "up to date", io.string
    assert_equal 0, code
  end

  test "reports not_installed and exits zero" do
    io = StringIO.new
    code = doctor(:not_installed, io).run

    assert_match "not installed", io.string
    assert_equal 0, code
  end

  test "reports error by naming the unparseable file, not the generator, and exits nonzero" do
    io = StringIO.new
    code = doctor(:error, io).run

    assert_match(/settings\.json|\.mcp\.json/, io.string)
    assert_no_match(/bin\/rails g rails_informant:skill/, io.string)
    assert_equal 1, code
  end

  test "refreshes the drift flag — writes when stale" do
    stale = mock("integration")
    stale.stubs(:status).returns(:stale)
    stale.expects(:write_drift_flag).with(stale: true)

    RailsInformant::Doctor.new(integration: stale, io: StringIO.new).run
  end

  test "refreshes the drift flag — clears when not stale" do
    current = mock("integration")
    current.stubs(:status).returns(:current)
    current.expects(:write_drift_flag).with(stale: false)

    RailsInformant::Doctor.new(integration: current, io: StringIO.new).run
  end

  private

  def doctor(status, io)
    integration = mock("integration")
    integration.stubs(:status).returns(status)
    integration.stubs(:write_drift_flag)
    RailsInformant::Doctor.new(integration: integration, io: io)
  end
end
