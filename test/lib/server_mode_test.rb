require "test_helper"

class RailsInformant::ServerModeTest < ActiveSupport::TestCase
  test "returns falsy in non-server context" do
    # Test environment does not boot Rails::Server, so this should be falsy
    # (matching console, rake, and runner contexts where Puma may still be defined)
    assert_not RailsInformant.server_mode?
  end

  test "returns truthy when Rails::Server is defined" do
    stub_const_rails_server do
      assert RailsInformant.server_mode?
    end
  end

  test "returns falsy even when Puma is defined" do
    # Puma gets loaded via Bundler.require in console/rake contexts.
    # server_mode? must not treat defined?(Puma) as evidence of a server boot.
    stub_const(:Puma, Module.new) do
      assert defined?(Puma), "Expected Puma to be defined"
      assert_not RailsInformant.server_mode?
    end
  end

  private

  def stub_const_rails_server
    refute defined?(Rails::Server), "Rails::Server should not be defined in test"
    Rails.const_set :Server, Class.new
    yield
  ensure
    Rails.send :remove_const, :Server
  end

  def stub_const(name, value)
    previously_defined = Object.const_defined?(name)
    Object.const_set name, value unless previously_defined
    yield
  ensure
    Object.send :remove_const, name unless previously_defined
  end
end
