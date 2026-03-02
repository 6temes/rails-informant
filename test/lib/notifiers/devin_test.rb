require "test_helper"

class RailsInformant::Notifiers::DevinTest < ActiveSupport::TestCase
  setup do
    @notifier = RailsInformant::Notifiers::Devin.new
    RailsInformant.config.devin_api_key = "test-devin-key"
    RailsInformant.config.devin_playbook_id = "pb-123"
  end

  # should_notify? — first-occurrence-only policy

  test "should_notify? returns true for first occurrence" do
    group = build_group total_occurrences: 1
    assert @notifier.should_notify?(group)
  end

  test "should_notify? returns false for second occurrence" do
    group = build_group total_occurrences: 2
    assert_not @notifier.should_notify?(group)
  end

  test "should_notify? returns false at milestone counts" do
    [ 10, 100, 1000 ].each do |count|
      group = build_group total_occurrences: count
      assert_not @notifier.should_notify?(group), "Expected false at count #{count}"
    end
  end

  # notify — HTTP request

  test "sends POST to Devin API with bearer auth" do
    group = create_group
    occurrence = group.occurrences.create! backtrace: [ "/app/foo.rb:1" ], git_sha: "abc123"

    request, _payload = capture_request(group, occurrence)

    assert_equal "Bearer test-devin-key", request["Authorization"]
    assert_equal "application/json", request["Content-Type"]
  end

  test "payload includes playbook_id and title" do
    group = create_group controller_action: "OrdersController#create"
    occurrence = group.occurrences.create! backtrace: [ "/app/foo.rb:1" ]

    _request, payload = capture_request(group, occurrence)

    assert_equal "pb-123", payload["playbook_id"]
    assert_equal "Fix: StandardError in OrdersController#create", payload["title"]
  end

  test "title falls back to job_class then unknown" do
    group = create_group job_class: "ImportJob"
    occurrence = group.occurrences.create! backtrace: [ "/app/foo.rb:1" ]

    _request, payload = capture_request(group, occurrence)
    assert_equal "Fix: StandardError in ImportJob", payload["title"]

    group2 = create_group
    occurrence2 = group2.occurrences.create! backtrace: [ "/app/foo.rb:1" ]

    _request2, payload2 = capture_request(group2, occurrence2)
    assert_equal "Fix: StandardError in unknown", payload2["title"]
  end

  test "prompt includes required error fields" do
    group = create_group
    occurrence = group.occurrences.create! backtrace: [ "/app/foo.rb:1" ], git_sha: "abc123"

    _request, payload = capture_request(group, occurrence)
    prompt = payload["prompt"]

    assert_includes prompt, "StandardError"
    assert_includes prompt, "test error"
    assert_includes prompt, "Error Group ID: #{group.id}"
    assert_includes prompt, "Git SHA: abc123"
    assert_includes prompt, "/app/foo.rb:1"
    assert_includes prompt, "get_error id: #{group.id}"
  end

  test "prompt truncates long messages to 500 chars" do
    long_message = "x" * 600
    group = create_group message: long_message
    occurrence = group.occurrences.create! backtrace: [ "/app/foo.rb:1" ]

    _request, payload = capture_request(group, occurrence)

    assert_not_includes payload["prompt"], long_message
    assert_includes payload["prompt"], "x" * 497 + "..."
  end

  test "prompt includes backtrace limited to 5 frames" do
    backtrace = (1..10).map { |i| "/app/file#{i}.rb:#{i}" }
    group = create_group
    occurrence = group.occurrences.create! backtrace:, git_sha: "abc123"

    _request, payload = capture_request(group, occurrence)

    assert_includes payload["prompt"], "/app/file5.rb:5"
    assert_not_includes payload["prompt"], "/app/file6.rb:6"
  end

  test "handles nil occurrence gracefully" do
    group = create_group

    _request, payload = capture_request(group, nil)

    assert_includes payload["prompt"], "StandardError"
    assert_not_includes payload["prompt"], "Git SHA"
    assert_not_includes payload["prompt"], "Backtrace"
  end

  # HTTP error handling

  test "raises on non-2xx response" do
    group = create_group
    occurrence = group.occurrences.create! backtrace: [ "/app/foo.rb:1" ]

    stub_devin_api response_class: Net::HTTPUnauthorized, code: "401", body: "Invalid API key"

    error = assert_raises(RuntimeError) { @notifier.notify group, occurrence }
    assert_includes error.message, "Devin API error: HTTP 401"
    assert_includes error.message, "Invalid API key"
  end

  test "raises on server error" do
    group = create_group
    occurrence = group.occurrences.create! backtrace: [ "/app/foo.rb:1" ]

    stub_devin_api response_class: Net::HTTPInternalServerError, code: "500", body: ""

    assert_raises(RuntimeError) { @notifier.notify group, occurrence }
  end

  # HTTP timeouts

  test "sets HTTP timeouts" do
    group = create_group
    occurrence = group.occurrences.create! backtrace: [ "/app/foo.rb:1" ]

    stub_http = stub_devin_api

    @notifier.notify group, occurrence

    assert_equal 10, stub_http.open_timeout
    assert_equal 15, stub_http.read_timeout
  end

  # NotifyJob integration

  test "NotifyJob includes Devin notifier when configured" do
    group = create_group
    group.occurrences.create! backtrace: [ "/app/foo.rb:1" ]

    stub_devin_api

    assert_nothing_raised { RailsInformant::NotifyJob.perform_now group.id }
  end

  test "NotifyJob skips Devin when api_key missing" do
    RailsInformant.config.devin_api_key = nil
    group = create_group
    group.occurrences.create! backtrace: [ "/app/foo.rb:1" ]

    Net::HTTP.expects(:start).never

    RailsInformant::NotifyJob.perform_now group.id
  end

  test "NotifyJob skips Devin when playbook_id missing" do
    RailsInformant.config.devin_playbook_id = nil
    group = create_group
    group.occurrences.create! backtrace: [ "/app/foo.rb:1" ]

    Net::HTTP.expects(:start).never

    RailsInformant::NotifyJob.perform_now group.id
  end

  private

    def build_group(total_occurrences: 1)
      RailsInformant::ErrorGroup.new(
        fingerprint: SecureRandom.hex(8),
        error_class: "StandardError",
        message: "test error",
        status: "unresolved",
        total_occurrences:,
        first_seen_at: Time.current,
        last_seen_at: Time.current
      )
    end

    def create_group(controller_action: nil, job_class: nil, message: "test error")
      RailsInformant::ErrorGroup.create!(
        fingerprint: SecureRandom.hex(8),
        error_class: "StandardError",
        message:,
        controller_action:,
        job_class:,
        first_seen_at: Time.current,
        last_seen_at: Time.current
      )
    end

    def stub_devin_api(response_class: Net::HTTPOK, code: "200", body: '{"session_id":"s-123"}')
      response = response_class.new("1.1", code, "")
      response.stubs(:body).returns(body)

      stub_http = StubHTTP.new(response)
      Net::HTTP.stubs(:start).yields(stub_http).returns(response)
      stub_http
    end

    def capture_request(group, occurrence)
      stub_http = stub_devin_api
      @notifier.notify group, occurrence
      request = stub_http.captured_request
      payload = JSON.parse(request.body)
      [ request, payload ]
    end

    class StubHTTP
      attr_accessor :open_timeout, :read_timeout
      attr_reader :captured_request

      def initialize(response)
        @response = response
      end

      def request(req)
        @captured_request = req
        @response
      end
    end
end
