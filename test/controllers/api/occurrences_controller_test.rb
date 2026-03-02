require "test_helper"

class RailsInformant::Api::OccurrencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @headers = { "Authorization" => "Bearer test-token-123" }
    @group = RailsInformant::ErrorGroup.create!(
      fingerprint: "test-fp",
      error_class: "StandardError",
      message: "test",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )
    @occurrence = @group.occurrences.create!(
      backtrace: [ "/app/foo.rb:1" ],
      git_sha: "abc123"
    )
  end

  test "index returns occurrences" do
    get "/informant/api/occurrences", headers: @headers
    assert_response :ok

    body = JSON.parse(response.body)
    assert_equal 1, body["data"].size
    assert_equal 1, body["meta"]["page"]
    assert_equal 20, body["meta"]["per_page"]
    assert_equal false, body["meta"]["has_more"]
  end

  test "filters by error_group_id" do
    other_group = RailsInformant::ErrorGroup.create!(
      fingerprint: "other-fp",
      error_class: "RuntimeError",
      message: "other",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )
    other_group.occurrences.create!(backtrace: [ "/app/bar.rb:1" ])

    get "/informant/api/occurrences", params: { error_group_id: @group.id }, headers: @headers
    assert_response :ok

    body = JSON.parse(response.body)
    assert_equal 1, body["data"].size
    assert_equal @group.id, body["data"].first["error_group_id"]
  end

  test "filters by since date" do
    old_occurrence = @group.occurrences.create!(backtrace: [ "/app/old.rb:1" ])
    old_occurrence.update_column(:created_at, 3.days.ago)

    get "/informant/api/occurrences", params: { since: 2.days.ago.iso8601 }, headers: @headers
    assert_response :ok

    body = JSON.parse(response.body)
    ids = body["data"].map { |o| o["id"] }
    assert_includes ids, @occurrence.id
    assert_not_includes ids, old_occurrence.id
  end

  test "filters by until date" do
    old_occurrence = @group.occurrences.create!(backtrace: [ "/app/old.rb:1" ])
    old_occurrence.update_column(:created_at, 3.days.ago)

    get "/informant/api/occurrences", params: { until: 2.days.ago.iso8601 }, headers: @headers
    assert_response :ok

    body = JSON.parse(response.body)
    ids = body["data"].map { |o| o["id"] }
    assert_includes ids, old_occurrence.id
    assert_not_includes ids, @occurrence.id
  end

  test "paginates results" do
    3.times { @group.occurrences.create!(backtrace: [ "/app/foo.rb:1" ]) }

    get "/informant/api/occurrences", params: { per_page: 2 }, headers: @headers
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal 2, body["data"].size
    assert_equal true, body["meta"]["has_more"]
  end
end
