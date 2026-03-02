require "test_helper"

class RailsInformant::Api::ErrorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @headers = { "Authorization" => "Bearer test-token-123" }
    @group = RailsInformant::ErrorGroup.create!(
      fingerprint: "test-fp",
      error_class: "StandardError",
      message: "test error",
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      total_occurrences: 1
    )
  end

  test "index returns error groups" do
    get "/informant/api/errors", headers: @headers
    assert_response :ok

    body = JSON.parse(response.body)
    assert_equal 1, body["data"].size
    assert_equal "StandardError", body["data"].first["error_class"]
    assert_equal 1, body["meta"]["page"]
    assert_equal 20, body["meta"]["per_page"]
    assert_equal false, body["meta"]["has_more"]
  end

  test "index filters by status" do
    get "/informant/api/errors", params: { status: "resolved" }, headers: @headers
    assert_response :ok
    assert_equal 0, JSON.parse(response.body)["data"].size
  end

  test "index filters by search" do
    get "/informant/api/errors", params: { q: "test" }, headers: @headers
    assert_response :ok
    assert_equal 1, JSON.parse(response.body)["data"].size
  end

  test "index paginates" do
    5.times { |i| create_group(fingerprint: "fp-#{i}") }
    get "/informant/api/errors", params: { per_page: 2 }, headers: @headers
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal 2, body["data"].size
    assert_equal true, body["meta"]["has_more"]
  end

  test "show returns group with occurrences" do
    @group.occurrences.create!(backtrace: [ "/app/foo.rb:1" ])

    get "/informant/api/errors/#{@group.id}", headers: @headers
    assert_response :ok

    body = JSON.parse(response.body)
    assert_equal "StandardError", body["error_class"]
    assert_equal 1, body["recent_occurrences"].size
  end

  test "update changes status" do
    patch "/informant/api/errors/#{@group.id}", params: { status: "resolved" }, headers: @headers, as: :json
    assert_response :ok

    @group.reload
    assert_equal "resolved", @group.status
    assert_not_nil @group.resolved_at
  end

  test "update rejects invalid transition" do
    @group.update_column(:status, "resolved")
    patch "/informant/api/errors/#{@group.id}", params: { status: "ignored" }, headers: @headers, as: :json
    assert_response :unprocessable_entity
  end

  test "update notes" do
    patch "/informant/api/errors/#{@group.id}", params: { notes: "investigating" }, headers: @headers, as: :json
    assert_response :ok

    @group.reload
    assert_equal "investigating", @group.notes
  end

  test "destroy deletes group" do
    assert_difference "RailsInformant::ErrorGroup.count", -1 do
      delete "/informant/api/errors/#{@group.id}", headers: @headers
    end
    assert_response :no_content
  end

  test "fix_pending sets fix metadata" do
    post "/informant/api/errors/#{@group.id}/fix_pending",
      params: { fix_sha: "abc123", original_sha: "def456", fix_pr_url: "https://github.com/pr/1" },
      headers: @headers, as: :json
    assert_response :ok

    @group.reload
    assert_equal "fix_pending", @group.status
    assert_equal "abc123", @group.fix_sha
    assert_equal "def456", @group.original_sha
  end

  test "fix_pending requires fix_sha and original_sha" do
    post "/informant/api/errors/#{@group.id}/fix_pending",
      params: { fix_sha: "abc123" },
      headers: @headers, as: :json
    assert_response :unprocessable_entity
  end

  test "duplicate marks as duplicate" do
    target = create_group(fingerprint: "target-fp")
    post "/informant/api/errors/#{@group.id}/duplicate",
      params: { duplicate_of_id: target.id },
      headers: @headers, as: :json
    assert_response :ok

    @group.reload
    assert_equal "duplicate", @group.status
    assert_equal target.id, @group.duplicate_of_id
  end

  test "duplicate rejects self-reference" do
    post "/informant/api/errors/#{@group.id}/duplicate",
      params: { duplicate_of_id: @group.id },
      headers: @headers, as: :json
    assert_response :unprocessable_entity
  end

  test "unauthorized without token" do
    get "/informant/api/errors"
    assert_response :unauthorized
  end

  test "unauthorized with wrong token" do
    get "/informant/api/errors", headers: { "Authorization" => "Bearer wrong" }
    assert_response :unauthorized
  end

  test "security headers present" do
    get "/informant/api/errors", headers: @headers
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
  end

  test "not found returns 404" do
    get "/informant/api/errors/999999", headers: @headers
    assert_response :not_found
  end

  test "index filters by until date" do
    old = create_group(fingerprint: "old-fp")
    old.update_column(:last_seen_at, 3.days.ago)

    get "/informant/api/errors", params: { until: 2.days.ago.iso8601 }, headers: @headers
    assert_response :ok

    body = JSON.parse(response.body)
    ids = body["data"].map { |e| e["id"] }
    assert_includes ids, old.id
    assert_not_includes ids, @group.id
  end

  test "index returns 400 for invalid since date" do
    get "/informant/api/errors", params: { since: "not-a-date" }, headers: @headers
    assert_response :bad_request

    body = JSON.parse(response.body)
    assert_match(/Invalid date format/, body["error"])
  end

  test "circular_duplicate? returns false for broken chain with nil target" do
    # When find_by returns nil for a broken chain link, circular_duplicate? should
    # return false instead of raising NoMethodError. This tests the safe navigation fix.
    controller = RailsInformant::Api::ErrorsController.new
    assert_equal false, controller.send(:circular_duplicate?, nil, @group.id)
  end

  private

  def create_group(fingerprint: SecureRandom.hex(8))
    RailsInformant::ErrorGroup.create!(
      fingerprint: fingerprint,
      error_class: "StandardError",
      message: "test",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )
  end
end
