require "test_helper"

class RailsInformant::IgnoredExceptionTest < ActiveSupport::TestCase
  test "ignores default exception by exact class name" do
    error = SystemExit.new("shutting down")
    assert RailsInformant.ignored_exception?(error)
  end

  test "ignores exception whose ancestor is in the default list" do
    custom_exit = Class.new(SystemExit)
    error = custom_exit.new("custom exit")
    assert RailsInformant.ignored_exception?(error)
  end

  test "ignores exception when a cause in the chain is ignored" do
    cause = SystemExit.new("shutting down")
    wrapper = RuntimeError.new("wrapped")
    wrapper.define_singleton_method(:cause) { cause }
    assert RailsInformant.ignored_exception?(wrapper)
  end

  test "ignores exception with deeply nested ignored cause" do
    root_cause = SystemExit.new("shutting down")
    middle = RuntimeError.new("middle")
    middle.define_singleton_method(:cause) { root_cause }
    outer = StandardError.new("outer")
    outer.define_singleton_method(:cause) { middle }
    assert RailsInformant.ignored_exception?(outer)
  end

  test "does not ignore unknown exceptions" do
    error = RuntimeError.new("boom")
    assert_not RailsInformant.ignored_exception?(error)
  end

  test "does not ignore RecordNotFound (a real bug off the request path)" do
    error = ActiveRecord::RecordNotFound.new("Couldn't find User with 'id'=999")
    assert_not RailsInformant.ignored_exception?(error)
  end

  test "does not ignore a DeserializationError caused by RecordNotFound" do
    error = deserialization_error_caused_by_record_not_found
    assert_not RailsInformant.ignored_exception?(error)
  end

  test "does not ignore UrlGenerationError (a real 500-class bug, not a Rails-handled response)" do
    error = ActionController::UrlGenerationError.new("missing required keys")
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

  private

  # Mirrors the incident: ActiveJob wraps a deserialization failure, and Ruby
  # sets the DeserializationError's cause to the in-flight RecordNotFound.
  def deserialization_error_caused_by_record_not_found
    begin
      raise ActiveRecord::RecordNotFound, "Couldn't find User with 'id'=999"
    rescue
      raise ActiveJob::DeserializationError
    end
  rescue ActiveJob::DeserializationError => error
    error
  end
end
