require "test_helper"

class RailsInformant::Api::DeploysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @headers = { "Authorization" => "Bearer test-token-00112233445566778899aabb" }
  end

  test "resolves stale unresolved errors" do
    stale = create_error_group(last_seen_at: 2.hours.ago)
    recent = create_error_group(last_seen_at: 30.minutes.ago)

    post "/informant/api/v1/deploy", params: { sha: "abc1234" }, headers: @headers
    assert_response :ok

    body = JSON.parse(response.body)
    assert_equal 1, body["resolved_count"]
    assert_equal "abc1234", body["sha"]

    assert_equal "resolved", stale.reload.status
    assert_equal "abc1234", stale.fix_sha
    assert_equal "unresolved", recent.reload.status
  end

  test "regression detection reopens resolved errors on reoccurrence" do
    group = create_error_group(last_seen_at: 2.hours.ago)

    post "/informant/api/v1/deploy", params: { sha: "abc1234" }, headers: @headers
    assert_equal "resolved", group.reload.status

    # Simulate reoccurrence
    group.detect_regression!
    assert_equal "unresolved", group.reload.status
  end

  test "requires sha parameter" do
    post "/informant/api/v1/deploy", params: {}, headers: @headers
    assert_response :bad_request
  end

  test "validates sha format" do
    post "/informant/api/v1/deploy", params: { sha: "not-a-sha!" }, headers: @headers
    assert_response :bad_request
  end

  test "returns zero when no stale errors exist" do
    create_error_group(last_seen_at: 10.minutes.ago)

    post "/informant/api/v1/deploy", params: { sha: "abc1234" }, headers: @headers
    assert_response :ok

    body = JSON.parse(response.body)
    assert_equal 0, body["resolved_count"]
  end

  test "does not resolve already-resolved or ignored errors" do
    resolved = create_error_group(last_seen_at: 2.hours.ago).tap do |g|
      g.update_columns status: "resolved", resolved_at: 1.hour.ago
    end
    ignored = create_error_group(last_seen_at: 2.hours.ago).tap do |g|
      g.update_column :status, "ignored"
    end

    post "/informant/api/v1/deploy", params: { sha: "abc1234" }, headers: @headers

    body = JSON.parse(response.body)
    assert_equal 0, body["resolved_count"]
    assert_equal "resolved", resolved.reload.status
    assert_equal "ignored", ignored.reload.status
  end

  test "requires authentication" do
    post "/informant/api/v1/deploy", params: { sha: "abc1234" }
    assert_response :unauthorized
  end
end
