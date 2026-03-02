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
end
