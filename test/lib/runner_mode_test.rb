require "test_helper"

class RailsInformant::RunnerModeTest < ActiveSupport::TestCase
  test "returns falsy in non-runner context" do
    # The test suite boots via rake, which never loads the runner command.
    assert_not RailsInformant.runner_mode?
  end

  test "returns truthy when Rails::Command::RunnerCommand is defined" do
    stub_const_runner_command do
      assert RailsInformant.runner_mode?
    end
  end

  private

  def stub_const_runner_command
    refute defined?(Rails::Command::RunnerCommand), "RunnerCommand should not be defined in test"
    Rails::Command.const_set :RunnerCommand, Class.new
    yield
  ensure
    Rails::Command.send :remove_const, :RunnerCommand
  end
end
