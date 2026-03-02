require "test_helper"

class RailsInformant::IgnoredExceptionTest < ActiveSupport::TestCase
  test "ignores default exception by exact class name" do
    error = ActiveRecord::RecordNotFound.new("not found")
    assert RailsInformant.ignored_exception?(error)
  end

  test "ignores exception whose ancestor is in the default list" do
    custom_not_found = Class.new(ActiveRecord::RecordNotFound)
    error = custom_not_found.new("custom not found")
    assert RailsInformant.ignored_exception?(error)
  end

  test "does not ignore unknown exceptions" do
    error = RuntimeError.new("boom")
    assert_not RailsInformant.ignored_exception?(error)
  end

  test "ignores user-configured string exceptions" do
    RailsInformant.config.ignored_exceptions = [ "RuntimeError" ]
    RailsInformant.reset_caches!

    error = RuntimeError.new("boom")
    assert RailsInformant.ignored_exception?(error)
  end

  test "memoizes ignored set as a frozen Set" do
    RailsInformant.ignored_exception?(StandardError.new)

    ignored_set = RailsInformant.instance_variable_get(:@_ignored_set)
    assert_kind_of Set, ignored_set
    assert ignored_set.frozen?
  end

  test "returns same memoized object across calls" do
    RailsInformant.ignored_exception?(StandardError.new)

    first = RailsInformant.instance_variable_get(:@_ignored_set)

    RailsInformant.ignored_exception?(StandardError.new)

    second = RailsInformant.instance_variable_get(:@_ignored_set)
    assert_same first, second
  end

  test "reset_caches! clears memoized matchers" do
    RailsInformant.ignored_exception?(StandardError.new)

    first = RailsInformant.instance_variable_get(:@_ignored_set)
    RailsInformant.reset_caches!

    RailsInformant.ignored_exception?(StandardError.new)

    second = RailsInformant.instance_variable_get(:@_ignored_set)
    refute_same first, second
  end
end
