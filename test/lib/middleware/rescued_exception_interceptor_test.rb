require "test_helper"

class RailsInformant::Middleware::RescuedExceptionInterceptorTest < ActiveSupport::TestCase
  test "stashes exception in env and re-raises" do
    error = StandardError.new("intercepted")
    app = ->(_env) { raise error }
    middleware = RailsInformant::Middleware::RescuedExceptionInterceptor.new(app)

    env = {}
    assert_raises(StandardError) do
      middleware.call(env)
    end

    assert_equal error, env["rails_informant.rescued_exception"]
  end

  test "passes through successful requests" do
    app = ->(_env) { [ 200, {}, [ "ok" ] ] }
    middleware = RailsInformant::Middleware::RescuedExceptionInterceptor.new(app)

    env = {}
    status, _headers, _body = middleware.call(env)
    assert_equal 200, status
    assert_nil env["rails_informant.rescued_exception"]
  end
end
