require "test_helper"

class RailsInformant::Middleware::ErrorCaptureTest < ActiveSupport::TestCase
  test "captures unhandled exception and marks as captured" do
    app = ->(_env) { raise StandardError, "unhandled" }
    middleware = RailsInformant::Middleware::ErrorCapture.new(app)

    error = assert_raises(StandardError) do
      middleware.call({})
    end

    assert error.instance_variable_get(:@__rails_informant_captured),
      "Expected exception to be marked as captured"
  end

  test "captures rescued exception from env" do
    error = StandardError.new("rescued")
    error.set_backtrace [ "/app/foo.rb:1" ]
    app = ->(env) {
      env["rails_informant.rescued_exception"] = error
      [ 200, {}, [ "" ] ]
    }
    middleware = RailsInformant::Middleware::ErrorCapture.new(app)

    middleware.call({})

    assert error.instance_variable_get(:@__rails_informant_captured),
      "Expected exception to be marked as captured"
  end

  test "skips already captured exceptions" do
    RailsInformant::ErrorRecorder.expects(:record).never

    error = StandardError.new("already captured")
    error.instance_variable_set(:@__rails_informant_captured, true)
    app = ->(_env) { raise error }
    middleware = RailsInformant::Middleware::ErrorCapture.new(app)

    assert_raises(StandardError) do
      middleware.call({})
    end
  end

  test "passes through successful requests" do
    RailsInformant::ErrorRecorder.expects(:record).never

    app = ->(_env) { [ 200, {}, [ "ok" ] ] }
    middleware = RailsInformant::Middleware::ErrorCapture.new(app)

    status, _headers, body = middleware.call({})
    assert_equal 200, status
    assert_equal [ "ok" ], body
  end
end
