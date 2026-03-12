require "test_helper"

class RailsInformant::EventTest < ActiveSupport::TestCase
  test "exposes error attributes" do
    error = StandardError.new("boom")
    attrs = { error_class: "StandardError", message: "boom", severity: "error",
              controller_action: "users#show", job_class: nil }
    env = { "PATH_INFO" => "/users/1" }

    event = RailsInformant::Event.new(error, attrs, env:)

    assert_equal error, event.error
    assert_equal "StandardError", event.error_class
    assert_equal "boom", event.message
    assert_equal "error", event.severity
    assert_equal "users#show", event.controller_action
    assert_nil event.job_class
    assert_equal "/users/1", event.request_path
  end

  test "halt! marks event as halted" do
    event = build_event
    assert_not event.halted?

    event.halt!
    assert event.halted?
  end

  test "fingerprint and severity are writable" do
    event = build_event
    event.fingerprint = "custom-fp"
    event.severity = "warning"

    assert_equal "custom-fp", event.fingerprint
    assert_equal "warning", event.severity
  end

  test "request_path is nil when env is nil" do
    event = RailsInformant::Event.new(StandardError.new, { error_class: "StandardError" }, env: nil)
    assert_nil event.request_path
  end

  private

  def build_event
    RailsInformant::Event.new(
      StandardError.new("boom"),
      { error_class: "StandardError", message: "boom", severity: "error" },
      env: {}
    )
  end
end
