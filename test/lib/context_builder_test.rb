require "test_helper"

class RailsInformant::ContextBuilderTest < ActiveSupport::TestCase
  # -- build_request_context --

  test "build_request_context extracts method, URL, IP, and headers" do
    env = rack_env(
      "REQUEST_METHOD" => "POST",
      "PATH_INFO" => "/users",
      "HTTP_HOST" => "example.com",
      "REMOTE_ADDR" => "192.168.1.1",
      "HTTP_ACCEPT" => "application/json",
      "HTTP_X_REQUEST_ID" => "req-abc"
    )

    ctx = RailsInformant::ContextBuilder.build_request_context(env)

    assert_equal "POST", ctx[:method]
    assert_includes ctx[:url], "/users"
    assert_equal "192.168.1.1", ctx[:ip]
    assert_equal "application/json", ctx[:headers]["Accept"]
    assert_equal "req-abc", ctx[:headers]["X-Request-Id"]
  end

  test "build_request_context returns nil when env is nil" do
    assert_nil RailsInformant::ContextBuilder.build_request_context(nil)
  end

  test "build_request_context excludes sensitive headers" do
    env = rack_env(
      "HTTP_HOST" => "example.com",
      "HTTP_AUTHORIZATION" => "Bearer secret-token",
      "HTTP_COOKIE" => "session=abc123",
      "HTTP_X_API_KEY" => "api-key-value",
      "HTTP_ACCEPT" => "text/html"
    )

    ctx = RailsInformant::ContextBuilder.build_request_context(env)

    assert_nil ctx[:headers]["Authorization"]
    assert_nil ctx[:headers]["Cookie"]
    assert_nil ctx[:headers]["X-Api-Key"]
    assert_equal "text/html", ctx[:headers]["Accept"]
  end

  # -- detect_current_user --

  test "detect_current_user extracts user from Current.user" do
    user = stub(id: 42, class: stub(name: "User"), email: "test@example.com")

    current_klass = stub
    current_klass.stubs(:respond_to?).with(:user).returns(true)
    current_klass.stubs(:user).returns(user)

    env = rack_env("HTTP_HOST" => "example.com")

    ctx = nil
    with_capture_user_email do
      with_current_stub(current_klass) do
        ctx = RailsInformant::ContextBuilder.build_user_context(env)
      end
    end

    assert_equal 42, ctx[:id]
    assert_equal "User", ctx[:class]
    assert_equal "test@example.com", ctx[:email]
  end

  test "detect_current_user extracts user from Warden" do
    user = stub(id: 99, class: stub(name: "Admin"), email: "admin@example.com")

    warden = stub(user: user)
    env = rack_env("HTTP_HOST" => "example.com", "warden" => warden)

    RailsInformant::Current.stubs(:user_context).returns(nil)

    ctx = nil
    with_capture_user_email do
      with_no_current do
        ctx = RailsInformant::ContextBuilder.build_user_context(env)
      end
    end

    assert_equal 99, ctx[:id]
    assert_equal "Admin", ctx[:class]
    assert_equal "admin@example.com", ctx[:email]
  end

  test "user_context does not include email by default" do
    user = stub(id: 42, class: stub(name: "User"), email: "test@example.com")

    current_klass = stub
    current_klass.stubs(:respond_to?).with(:user).returns(true)
    current_klass.stubs(:user).returns(user)

    env = rack_env("HTTP_HOST" => "example.com")

    ctx = nil
    with_current_stub(current_klass) do
      ctx = RailsInformant::ContextBuilder.build_user_context(env)
    end

    assert_equal 42, ctx[:id]
    assert_equal "User", ctx[:class]
    assert_nil ctx[:email]
  end

  test "detect_current_user returns nil when no user is available" do
    env = rack_env("HTTP_HOST" => "example.com")
    RailsInformant::Current.stubs(:user_context).returns(nil)

    ctx = nil
    with_no_current do
      ctx = RailsInformant::ContextBuilder.build_user_context(env)
    end

    assert_nil ctx
  end

  # -- build_custom_context --

  test "build_custom_context merges to_informant_context from exception" do
    error = StandardError.new("boom")
    error.define_singleton_method(:to_informant_context) { { payment_id: 42, gateway: "stripe" } }

    ctx = RailsInformant::ContextBuilder.build_custom_context(error)

    assert_equal 42, ctx[:payment_id]
    assert_equal "stripe", ctx[:gateway]
  end

  test "build_custom_context combines Current.custom_context with exception context" do
    error = StandardError.new("boom")
    error.define_singleton_method(:to_informant_context) { { from_error: true } }

    RailsInformant::Current.custom_context = { from_current: true }
    ctx = RailsInformant::ContextBuilder.build_custom_context(error)

    assert ctx[:from_current]
    assert ctx[:from_error]
  end

  test "build_custom_context returns nil when no context available" do
    error = StandardError.new("boom")
    RailsInformant::Current.custom_context = nil

    ctx = RailsInformant::ContextBuilder.build_custom_context(error)

    assert_nil ctx
  end

  # -- filtered_url --

  test "filtered_url filters sensitive query parameters" do
    env = rack_env(
      "HTTP_HOST" => "example.com",
      "PATH_INFO" => "/search",
      "QUERY_STRING" => "name=test&password=secret123&secret=hidden"
    )

    ctx = RailsInformant::ContextBuilder.build_request_context(env)

    uri = URI.parse(ctx[:url])
    params = Rack::Utils.parse_query(uri.query)

    assert_equal "test", params["name"]
    assert_equal "[FILTERED]", params["password"]
    assert_equal "[FILTERED]", params["secret"]
  end

  test "filtered_url strips query params from malformed URI" do
    url = "https://example.com/search?password=secret123&name=test"

    URI.stubs(:parse).raises(URI::InvalidURIError)
    result = RailsInformant::ContextBuilder.filtered_url(url)

    assert_not_includes result, "password"
    assert_not_includes result, "secret123"
    assert_not_includes result, "?"
    assert_includes result, "/search"
  ensure
    URI.unstub(:parse)
  end

  test "filtered_url works with no query string" do
    env = rack_env(
      "HTTP_HOST" => "example.com",
      "PATH_INFO" => "/users"
    )

    ctx = RailsInformant::ContextBuilder.build_request_context(env)

    assert_includes ctx[:url], "/users"
    assert_not_includes ctx[:url], "?"
  end

  private

  def rack_env(overrides = {})
    defaults = {
      "REQUEST_METHOD" => "GET",
      "SERVER_NAME" => "example.com",
      "SERVER_PORT" => "443",
      "PATH_INFO" => "/",
      "rack.url_scheme" => "https",
      "rack.input" => StringIO.new,
      "QUERY_STRING" => "",
      "action_dispatch.request.parameters" => {}
    }
    defaults.merge(overrides)
  end

  def with_capture_user_email
    RailsInformant.config.capture_user_email = true
    yield
  ensure
    RailsInformant.config.capture_user_email = false
  end

  def with_current_stub(current_klass)
    original_current = ::Current if defined?(::Current)
    silence_warnings { Object.const_set(:Current, current_klass) }
    yield
  ensure
    if original_current
      silence_warnings { Object.const_set(:Current, original_current) }
    else
      Object.send(:remove_const, :Current) if defined?(::Current)
    end
  end

  def with_no_current
    if defined?(::Current)
      original = ::Current
      Object.send(:remove_const, :Current)
      yield
      silence_warnings { Object.const_set(:Current, original) }
    else
      yield
    end
  end
end
