require "test_helper"

class RailsInformant::Api::ErrorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @headers = { "Authorization" => "Bearer test-token-00112233445566778899aabb" }
    @group = create_error_group(fingerprint: "test-fp", message: "test error")
  end

  test "index returns error groups" do
    get "/informant/api/v1/errors", headers: @headers
    assert_response :ok

    body = JSON.parse(response.body)
    assert_equal 1, body["data"].size
    assert_equal "StandardError", body["data"].first["error_class"]
    assert_equal 1, body["meta"]["page"]
    assert_equal 20, body["meta"]["per_page"]
    assert_equal false, body["meta"]["has_more"]
  end

  test "index filters by status" do
    get "/informant/api/v1/errors", params: { status: "resolved" }, headers: @headers
    assert_response :ok
    assert_equal 0, JSON.parse(response.body)["data"].size
  end

  test "index filters by duplicate status" do
    target = create_error_group(fingerprint: "target-fp")
    dup = create_error_group(fingerprint: "dup-fp")
    dup.update! status: "duplicate", duplicate_of: target

    get "/informant/api/v1/errors", params: { status: "duplicate" }, headers: @headers
    assert_response :ok

    body = JSON.parse(response.body)
    ids = body["data"].map { it["id"] }
    assert_includes ids, dup.id
    assert_not_includes ids, @group.id
    assert_not_includes ids, target.id
  end

  test "index excludes duplicates by default" do
    target = create_error_group(fingerprint: "target-fp")
    dup = create_error_group(fingerprint: "dup-fp")
    dup.update! status: "duplicate", duplicate_of: target

    get "/informant/api/v1/errors", headers: @headers
    assert_response :ok

    body = JSON.parse(response.body)
    ids = body["data"].map { it["id"] }
    assert_not_includes ids, dup.id
    assert_includes ids, @group.id
    assert_includes ids, target.id
  end

  test "index filters by search" do
    get "/informant/api/v1/errors", params: { q: "test" }, headers: @headers
    assert_response :ok
    assert_equal 1, JSON.parse(response.body)["data"].size
  end

  test "index paginates" do
    5.times { |i| create_error_group(fingerprint: "fp-#{i}") }
    get "/informant/api/v1/errors", params: { per_page: 2 }, headers: @headers
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal 2, body["data"].size
    assert_equal true, body["meta"]["has_more"]
  end

  test "show returns group with occurrences" do
    @group.occurrences.create!(backtrace: [ "/app/foo.rb:1" ])

    get "/informant/api/v1/errors/#{@group.id}", headers: @headers
    assert_response :ok

    body = JSON.parse(response.body)
    assert_equal "StandardError", body["error_class"]
    assert_equal 1, body["recent_occurrences"].size
  end

  test "update changes status" do
    patch "/informant/api/v1/errors/#{@group.id}", params: { status: "resolved" }, headers: @headers, as: :json
    assert_response :ok

    @group.reload
    assert_equal "resolved", @group.status
    assert_not_nil @group.resolved_at
  end

  test "update rejects invalid transition" do
    @group.update_column(:status, "resolved")
    patch "/informant/api/v1/errors/#{@group.id}", params: { status: "ignored" }, headers: @headers, as: :json
    assert_response :unprocessable_entity
  end

  test "update notes" do
    patch "/informant/api/v1/errors/#{@group.id}", params: { notes: "investigating" }, headers: @headers, as: :json
    assert_response :ok

    @group.reload
    assert_equal "investigating", @group.notes
  end

  test "update rejects notes exceeding length limit" do
    patch "/informant/api/v1/errors/#{@group.id}", params: { notes: "a" * 10_001 }, headers: @headers, as: :json
    assert_response :unprocessable_entity

    body = JSON.parse(response.body)
    assert_match(/Notes/, body["error"])
  end

  test "destroy deletes group" do
    assert_difference "RailsInformant::ErrorGroup.count", -1 do
      delete "/informant/api/v1/errors/#{@group.id}", headers: @headers
    end
    assert_response :no_content
  end

  test "destroy rejects deleting a duplicate target" do
    dup = create_error_group(fingerprint: "dup-fp")
    dup.update! status: "duplicate", duplicate_of: @group

    assert_no_difference "RailsInformant::ErrorGroup.count" do
      delete "/informant/api/v1/errors/#{@group.id}", headers: @headers
    end
    assert_response :unprocessable_entity

    body = JSON.parse(response.body)
    assert_match(/duplicate target/, body["error"])
  end

  test "fix_pending sets fix metadata" do
    patch "/informant/api/v1/errors/#{@group.id}/fix_pending",
      params: { fix_sha: "abc1234", original_sha: "def4567", fix_pr_url: "https://github.com/pr/1" },
      headers: @headers, as: :json
    assert_response :ok

    @group.reload
    assert_equal "fix_pending", @group.status
    assert_equal "abc1234", @group.fix_sha
    assert_equal "def4567", @group.original_sha
  end

  test "fix_pending requires original_sha" do
    patch "/informant/api/v1/errors/#{@group.id}/fix_pending",
      params: { fix_sha: "abc1234" },
      headers: @headers, as: :json
    assert_response :bad_request
    assert_match(/original_sha is required/, JSON.parse(response.body)["error"])
  end

  test "fix_pending requires fix_sha" do
    patch "/informant/api/v1/errors/#{@group.id}/fix_pending",
      params: { original_sha: "abc1234" },
      headers: @headers, as: :json
    assert_response :bad_request
    assert_match(/fix_sha is required/, JSON.parse(response.body)["error"])
  end

  test "fix_pending rejects invalid SHA format" do
    patch "/informant/api/v1/errors/#{@group.id}/fix_pending",
      params: { fix_sha: "not-a-sha!", original_sha: "abc1234" },
      headers: @headers, as: :json
    assert_response :bad_request
    assert_match(/Invalid SHA format/, JSON.parse(response.body)["error"])
  end

  test "fix_pending rejects non-HTTPS URL scheme" do
    patch "/informant/api/v1/errors/#{@group.id}/fix_pending",
      params: { fix_sha: "abc1234", original_sha: "def4567", fix_pr_url: "ftp://example.com" },
      headers: @headers, as: :json
    assert_response :bad_request
    assert_match(/Only HTTPS URLs are allowed/, JSON.parse(response.body)["error"])
  end

  test "fix_pending rejects HTTP URL" do
    patch "/informant/api/v1/errors/#{@group.id}/fix_pending",
      params: { fix_sha: "abc1234", original_sha: "def4567", fix_pr_url: "http://github.com/pr/1" },
      headers: @headers, as: :json
    assert_response :bad_request
    assert_match(/Only HTTPS URLs are allowed/, JSON.parse(response.body)["error"])
  end

  test "fix_pending rejects invalid transition via model validation" do
    @group.update_column :status, "resolved"
    patch "/informant/api/v1/errors/#{@group.id}/fix_pending",
      params: { fix_sha: "abc1234", original_sha: "def4567" },
      headers: @headers, as: :json
    assert_response :unprocessable_entity
  end

  test "duplicate marks as duplicate" do
    target = create_error_group(fingerprint: "target-fp")
    patch "/informant/api/v1/errors/#{@group.id}/duplicate",
      params: { duplicate_of_id: target.id },
      headers: @headers, as: :json
    assert_response :ok

    @group.reload
    assert_equal "duplicate", @group.status
    assert_equal target.id, @group.duplicate_of_id
  end

  test "duplicate rejects self-reference" do
    patch "/informant/api/v1/errors/#{@group.id}/duplicate",
      params: { duplicate_of_id: @group.id },
      headers: @headers, as: :json
    assert_response :bad_request
  end

  test "returns 503 when api_token not configured" do
    RailsInformant.config.api_token = nil
    get "/informant/api/v1/errors"
    assert_response :service_unavailable

    body = JSON.parse(response.body)
    assert_equal "API token not configured", body["error"]
  end

  test "unauthorized without token" do
    get "/informant/api/v1/errors"
    assert_response :unauthorized
  end

  test "unauthorized with wrong token" do
    get "/informant/api/v1/errors", headers: { "Authorization" => "Bearer wrong" }
    assert_response :unauthorized
  end

  test "security headers present" do
    get "/informant/api/v1/errors", headers: @headers
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "default-src 'none'", response.headers["Content-Security-Policy"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "DENY", response.headers["X-Frame-Options"]
  end

  test "not found returns 404" do
    get "/informant/api/v1/errors/999999", headers: @headers
    assert_response :not_found
  end

  test "index filters by until date" do
    old = create_error_group(fingerprint: "old-fp")
    old.update_column(:last_seen_at, 3.days.ago)

    get "/informant/api/v1/errors", params: { until: 2.days.ago.iso8601 }, headers: @headers
    assert_response :ok

    body = JSON.parse(response.body)
    ids = body["data"].map { |e| e["id"] }
    assert_includes ids, old.id
    assert_not_includes ids, @group.id
  end

  test "index filters by since date" do
    old = create_error_group(fingerprint: "old-fp")
    old.update_column(:last_seen_at, 3.days.ago)

    get "/informant/api/v1/errors", params: { since: 2.days.ago.iso8601 }, headers: @headers
    assert_response :ok

    ids = JSON.parse(response.body)["data"].map { it["id"] }
    assert_includes ids, @group.id
    assert_not_includes ids, old.id
  end

  test "index filters by error_class" do
    other = create_error_group(fingerprint: "other-fp", error_class: "NoMethodError")

    get "/informant/api/v1/errors", params: { error_class: "NoMethodError" }, headers: @headers
    assert_response :ok

    ids = JSON.parse(response.body)["data"].map { it["id"] }
    assert_includes ids, other.id
    assert_not_includes ids, @group.id
  end

  test "index filters by controller_action" do
    with_action = create_error_group(fingerprint: "action-fp", controller_action: "users#show")

    get "/informant/api/v1/errors", params: { controller_action: "users#show" }, headers: @headers
    assert_response :ok

    ids = JSON.parse(response.body)["data"].map { it["id"] }
    assert_includes ids, with_action.id
    assert_not_includes ids, @group.id
  end

  test "index filters by job_class" do
    with_job = create_error_group(fingerprint: "job-fp", job_class: "ImportJob")

    get "/informant/api/v1/errors", params: { job_class: "ImportJob" }, headers: @headers
    assert_response :ok

    ids = JSON.parse(response.body)["data"].map { it["id"] }
    assert_includes ids, with_job.id
    assert_not_includes ids, @group.id
  end

  test "index filters by severity" do
    warning = create_error_group(fingerprint: "warn-fp", severity: "warning")

    get "/informant/api/v1/errors", params: { severity: "warning" }, headers: @headers
    assert_response :ok

    ids = JSON.parse(response.body)["data"].map { it["id"] }
    assert_includes ids, warning.id
    assert_not_includes ids, @group.id
  end

  test "index returns 400 for invalid since date" do
    get "/informant/api/v1/errors", params: { since: "not-a-date" }, headers: @headers
    assert_response :bad_request

    body = JSON.parse(response.body)
    assert_match(/Invalid date format/, body["error"])
  end
end
