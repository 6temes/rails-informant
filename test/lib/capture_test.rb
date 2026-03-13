require "test_helper"

class RailsInformant::CaptureTest < ActiveSupport::TestCase
  test "capture records error without request" do
    error = build_error

    RailsInformant::ErrorRecorder.expects(:record).with(error, severity: "error", context: {}, env: nil)
    RailsInformant.capture error
  end

  test "capture forwards both request and context" do
    error = build_error
    env = { "REQUEST_METHOD" => "POST" }
    request = stub(env: env)
    custom_context = { user_id: 42 }

    RailsInformant::ErrorRecorder.expects(:record).with(error, severity: "error", context: custom_context, env: env)
    RailsInformant.capture error, context: custom_context, request: request
  end

  test "capture only records once for the same exception" do
    error = build_error

    RailsInformant::ErrorRecorder.expects(:record).once
    RailsInformant.capture error
    RailsInformant.capture error
  end

  test "already_captured? returns false for fresh error" do
    assert_not RailsInformant.already_captured?(build_error)
  end

  test "already_captured? returns true after mark_captured!" do
    error = build_error
    RailsInformant.mark_captured! error
    assert RailsInformant.already_captured?(error)
  end

  test "mark_captured! skips frozen errors" do
    error = build_error.freeze
    RailsInformant.mark_captured! error
    assert_not RailsInformant.already_captured?(error)
  end

  test "silence block sets Current.silenced for duration" do
    assert_not RailsInformant::Current.silenced

    RailsInformant.silence do
      assert RailsInformant::Current.silenced
    end

    assert_not RailsInformant::Current.silenced
  end

  test "silence block resets on exception" do
    assert_raises(RuntimeError) do
      RailsInformant.silence { raise "boom" }
    end

    assert_not RailsInformant::Current.silenced
  end

  test "nested silence blocks restore correctly" do
    RailsInformant.silence do
      RailsInformant.silence do
        assert RailsInformant::Current.silenced
      end
      assert RailsInformant::Current.silenced
    end

    assert_not RailsInformant::Current.silenced
  end

  test "silence block prevents capture" do
    error = build_error
    RailsInformant::ErrorRecorder.expects(:record).never

    RailsInformant.silence do
      RailsInformant.capture error
    end
  end

  private

  def build_error
    error = StandardError.new("boom")
    error.set_backtrace [ "/app/models/user.rb:42" ]
    error
  end
end
