require "test_helper"

class RailsInformant::Api::OccurrencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @headers = { "Authorization" => "Bearer test-token-00112233445566778899aabb" }
    @group = create_error_group(fingerprint: "test-fp")
    @occurrence = create_occurrence(error_group: @group, backtrace: [ "/app/foo.rb:1" ], git_sha: "abc123")
  end

  test "index returns occurrences" do
    get "/informant/api/v1/occurrences", headers: @headers
    assert_response :ok

    body = JSON.parse(response.body)
    assert_equal 1, body["data"].size
    assert_equal 1, body["meta"]["page"]
    assert_equal 20, body["meta"]["per_page"]
    assert_equal false, body["meta"]["has_more"]
  end

  test "filters by error_group_id" do
    other_group = create_error_group(fingerprint: "other-fp", error_class: "RuntimeError", message: "other")
    create_occurrence(error_group: other_group, backtrace: [ "/app/bar.rb:1" ])

    get "/informant/api/v1/occurrences", params: { error_group_id: @group.id }, headers: @headers
    assert_response :ok

    body = JSON.parse(response.body)
    assert_equal 1, body["data"].size
    assert_equal @group.id, body["data"].first["error_group_id"]
  end

  test "filters by since date" do
    old_occurrence = @group.occurrences.create!(backtrace: [ "/app/old.rb:1" ])
    old_occurrence.update_column(:created_at, 3.days.ago)

    get "/informant/api/v1/occurrences", params: { since: 2.days.ago.iso8601 }, headers: @headers
    assert_response :ok

    body = JSON.parse(response.body)
    ids = body["data"].map { |o| o["id"] }
    assert_includes ids, @occurrence.id
    assert_not_includes ids, old_occurrence.id
  end

  test "filters by until date" do
    old_occurrence = @group.occurrences.create!(backtrace: [ "/app/old.rb:1" ])
    old_occurrence.update_column(:created_at, 3.days.ago)

    get "/informant/api/v1/occurrences", params: { until: 2.days.ago.iso8601 }, headers: @headers
    assert_response :ok

    body = JSON.parse(response.body)
    ids = body["data"].map { |o| o["id"] }
    assert_includes ids, old_occurrence.id
    assert_not_includes ids, @occurrence.id
  end

  test "filters by request_id across the server and browser occurrences of one request" do
    server = create_occurrence(error_group: @group, request_id: "req-500")
    browser_group = create_error_group(fingerprint: "browser-fp", error_class: "JS::TypeError", source: "browser")
    browser = create_occurrence(error_group: browser_group, request_id: "req-render", failing_request_id: "req-500")

    get "/informant/api/v1/occurrences", params: { request_id: "req-500" }, headers: @headers
    assert_response :ok

    data = JSON.parse(response.body)["data"]
    assert_equal [ browser.id, server.id ].sort, data.map { it["id"] }.sort
    assert_equal "req-500", data.find { it["id"] == server.id }["request_id"]
    assert_equal "req-500", data.find { it["id"] == browser.id }["failing_request_id"]
  end

  test "paginates results" do
    3.times { @group.occurrences.create!(backtrace: [ "/app/foo.rb:1" ]) }

    get "/informant/api/v1/occurrences", params: { per_page: 2 }, headers: @headers
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal 2, body["data"].size
    assert_equal true, body["meta"]["has_more"]
  end
end
