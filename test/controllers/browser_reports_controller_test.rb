require "test_helper"

class RailsInformant::BrowserReportsControllerTest < ActionDispatch::IntegrationTest
  PATH = "/informant/browser_reports"
  SAME_ORIGIN = { "Content-Type" => "application/json", "Sec-Fetch-Site" => "same-origin" }.freeze

  setup do
    RailsInformant.config.capture_browser_errors = true
    RailsInformant::ErrorRecorder.reset_spike_counters!
    RailsInformant::BrowserReportsController.schema_warning_logged = false
    @cache_store = RailsInformant::BrowserReportsController.cache_store
    RailsInformant::BrowserReportsController.cache_store = :null_store
  end

  teardown do
    RailsInformant::BrowserReportsController.cache_store = @cache_store
  end

  test "a same-origin report is recorded as one browser group and occurrence" do
    assert_difference -> { RailsInformant::ErrorGroup.count } => 1,
                      -> { RailsInformant::Occurrence.count } => 1 do
      post_reports report
    end

    assert_response :no_content
    assert_empty response.body
    assert_equal "browser", RailsInformant::ErrorGroup.last.source
  end

  test "an Origin equal to the base URL passes when Sec-Fetch-Site is absent" do
    assert_difference -> { RailsInformant::ErrorGroup.count } => 1 do
      post_reports report, headers: { "Content-Type" => "application/json", "Origin" => "http://www.example.com" }
    end

    assert_response :no_content
  end

  test "a beacon's text/plain body is accepted" do
    assert_difference -> { RailsInformant::ErrorGroup.count } => 1 do
      post_reports report, headers: SAME_ORIGIN.merge("Content-Type" => "text/plain;charset=UTF-8")
    end

    assert_response :no_content
  end

  test "cross-site requests are rejected and record nothing" do
    [
      { "Sec-Fetch-Site" => "cross-site", "Origin" => "http://www.example.com" },
      { "Sec-Fetch-Site" => "same-site" },
      { "Origin" => "https://evil.example" },
      {}
    ].each do |headers|
      assert_no_difference -> { RailsInformant::ErrorGroup.count } do
        post_reports report, headers: headers.merge("Content-Type" => "application/json")
      end

      assert_response :forbidden, headers.inspect
    end
  end

  test "malformed bodies return 400 and record nothing" do
    [ "{not json", "[]", { reports: [ report ] }.to_json, { v: 1, reports: "nope" }.to_json ].each do |body|
      assert_no_difference -> { RailsInformant::ErrorGroup.count } do
        post PATH, params: body, headers: SAME_ORIGIN
      end

      assert_response :bad_request, body
    end
  end

  test "a body over 64 KB returns 413 and records nothing" do
    assert_no_difference -> { RailsInformant::ErrorGroup.count } do
      post_reports report("message" => "x" * 65.kilobytes)
    end

    assert_response :content_too_large
  end

  test "only the first 10 reports in a request are recorded" do
    reports = ("a".."l").map { report("message" => "failure #{it}") }

    assert_difference -> { RailsInformant::ErrorGroup.count } => 10 do
      post_reports(*reports)
    end

    assert_response :no_content
  end

  test "reports missing a name or message are skipped" do
    assert_difference -> { RailsInformant::ErrorGroup.count } => 1 do
      post_reports report.except("name"), report.except("message"), "not a report", report
    end
  end

  test "the 31st request from one IP within a minute returns 429" do
    RailsInformant::BrowserReportsController.cache_store = :memory_store

    30.times do
      post_reports
      assert_response :no_content
    end

    post_reports
    assert_response :too_many_requests
  end

  test "a valid blob supplies the user, revision and rendering request ID" do
    RailsInformant.stubs(:current_git_sha).returns("abc1234")
    blob = context_blob(request_id: "req-render", user_context: { id: 7, class: "User" })

    post_reports report("context" => blob, "request_id" => "forged", "user_context" => { "id" => 1 })

    occurrence = RailsInformant::Occurrence.last
    assert_equal({ "class" => "User", "id" => 7 }, occurrence.user_context)
    assert_equal "abc1234", occurrence.git_sha
    assert_equal "req-render", occurrence.request_id
  end

  test "a tampered or day-old blob records the report without user or rendering request ID" do
    fresh = context_blob(request_id: "req-render", user_context: { id: 7 })
    tampered = fresh.sub(/\A./) { it == "A" ? "B" : "A" }
    old = travel_to(25.hours.ago) { context_blob(request_id: "req-old", user_context: { id: 7 }) }

    [ tampered, old ].each do |blob|
      assert_difference -> { RailsInformant::ErrorGroup.count } => 1 do
        post_reports report("context" => blob, "message" => "failure #{blob == old ? "old" : "tampered"}",
          "request_id" => "forged", "user_context" => { "id" => 1 })
      end

      occurrence = RailsInformant::Occurrence.last
      assert_nil occurrence.user_context
      assert_nil occurrence.request_id
    end
  end

  test "with browser capture off the route does not exist" do
    RailsInformant.config.capture_browser_errors = false

    assert_no_difference -> { RailsInformant::ErrorGroup.count } do
      post_reports report
    end

    assert_response :not_found
  end

  test "before the browser migration runs it answers 503, records nothing and logs the generator once" do
    RailsInformant.stubs(:browser_schema_ready?).returns(false)
    Rails.logger.expects(:warn).with(includes("rails_informant:browser")).once

    assert_no_difference -> { RailsInformant::ErrorGroup.count } do
      2.times do
        post_reports report
        assert_response :service_unavailable
      end
    end
  end

  test "an exception raised while ingesting is not recorded as a server error" do
    RailsInformant::BrowserContext.stubs(:verify).raises(RuntimeError, "ingest exploded")

    assert_no_difference -> { RailsInformant::ErrorGroup.count } do
      assert_raises(RuntimeError) { post_reports report }
    end
  end

  test "security headers on accepted and rejected requests match the API's" do
    get "/informant/api/v1/status", headers: { "Authorization" => "Bearer test-token-00112233445566778899aabb" }
    expected = security_headers

    post_reports report
    assert_response :no_content
    assert_equal expected, security_headers
    assert_equal "no-store", response.headers["Cache-Control"]

    post_reports report, headers: { "Content-Type" => "application/json", "Sec-Fetch-Site" => "cross-site" }
    assert_response :forbidden
    assert_equal expected, security_headers
  end

  private

  def context_blob(request_id:, user_context:)
    RailsInformant::Current.user_context = user_context
    request = ActionDispatch::TestRequest.create("action_dispatch.request_id" => request_id)
    RailsInformant::BrowserContext.generate(request)
  ensure
    RailsInformant::Current.user_context = nil
  end

  def post_reports(*reports, headers: SAME_ORIGIN)
    post PATH, params: { v: 1, reports: }.to_json, headers:
  end

  def report(overrides = {})
    {
      "kind" => "error",
      "message" => "Cannot read properties of null (reading 'value')",
      "name" => "TypeError",
      "occurred_at" => "2026-11-01T10:00:01.000Z",
      "stack" => "",
      "url" => "http://www.example.com/cart"
    }.merge(overrides)
  end

  def security_headers
    response.headers.to_h.slice("Cache-Control", "Content-Security-Policy", "X-Content-Type-Options", "X-Frame-Options")
  end
end
