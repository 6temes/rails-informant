require "test_helper"

class RailsInformant::Api::StatusControllerTest < ActionDispatch::IntegrationTest
  setup do
    @headers = { "Authorization" => "Bearer test-token-00112233445566778899aabb" }
  end

  test "returns status summary" do
    3.times { |i| create_error_group(fingerprint: "fp-#{i}") }
    create_error_group(fingerprint: "fp-resolved", status: "unresolved").tap do |g|
      g.update_columns(status: "resolved", resolved_at: Time.current)
    end

    get "/informant/api/v1/status", headers: @headers
    assert_response :ok

    body = JSON.parse(response.body)
    assert_equal 0, body["duplicate_count"]
    assert_equal 3, body["unresolved_count"]
    assert_equal 1, body["resolved_count"]
    assert body.key?("deploy_sha")
    assert body.key?("top_errors")
  end

  test "top_errors limited to 5" do
    10.times { |i| create_error_group(fingerprint: "fp-#{i}") }

    get "/informant/api/v1/status", headers: @headers
    body = JSON.parse(response.body)
    assert_equal 5, body["top_errors"].size
  end

  test "reports the browser new-group cap when browser capture is on" do
    RailsInformant.config.capture_browser_errors = true
    RailsInformant.config.browser_new_group_limit = 10
    2.times { |i| create_error_group(fingerprint: "browser-#{i}", source: "browser") }
    create_error_group(fingerprint: "browser-old", source: "browser", created_at: 2.hours.ago)
    create_error_group(fingerprint: "server-fp")

    get "/informant/api/v1/status", headers: @headers

    body = JSON.parse(response.body)
    assert_equal 2, body["browser_groups_created_this_hour"]
    assert_equal 10, body["browser_new_group_limit"]
  end

  test "omits the browser new-group cap while the browser migration has not run" do
    RailsInformant.config.capture_browser_errors = true
    RailsInformant.stubs(:browser_schema_ready?).returns(false)
    RailsInformant::ErrorGroup.stubs(:browser_created_this_hour).raises(ActiveRecord::StatementInvalid, "no such column: source")

    get "/informant/api/v1/status", headers: @headers

    assert_response :ok
    assert_not JSON.parse(response.body).key?("browser_groups_created_this_hour")
  end

  test "omits the browser new-group cap when browser capture is off" do
    get "/informant/api/v1/status", headers: @headers

    body = JSON.parse(response.body)
    assert_not body.key?("browser_groups_created_this_hour")
    assert_not body.key?("browser_new_group_limit")
  end
end
