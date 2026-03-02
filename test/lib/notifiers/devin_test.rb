require "test_helper"

class RailsInformant::Notifiers::DevinTest < ActiveSupport::TestCase
  include StubHTTPHelpers

  setup do
    @notifier = RailsInformant::Notifiers::Devin.new
    RailsInformant.config.devin_api_key = "test-devin-key"
    RailsInformant.config.devin_playbook_id = "pb-123"
  end

  # should_notify? — first-occurrence-only policy

  test "should_notify? returns true for first occurrence" do
    group = build_error_group total_occurrences: 1
    assert @notifier.should_notify?(group)
  end

  test "should_notify? returns false for second occurrence" do
    group = build_error_group total_occurrences: 2
    assert_not @notifier.should_notify?(group)
  end

  test "should_notify? returns false at milestone counts" do
    [ 10, 100, 1000 ].each do |count|
      group = build_error_group total_occurrences: count
      assert_not @notifier.should_notify?(group), "Expected false at count #{count}"
    end
  end

  # notify — HTTP request

  test "sends POST to Devin API with bearer auth" do
    group = create_error_group
    occurrence = group.occurrences.create! backtrace: [ "/app/foo.rb:1" ], git_sha: "abc123"

    request, _payload = capture_request(group, occurrence)

    assert_equal "Bearer test-devin-key", request["Authorization"]
    assert_equal "application/json", request["Content-Type"]
  end

  test "payload includes playbook_id and title" do
    group = create_error_group controller_action: "OrdersController#create"
    occurrence = group.occurrences.create! backtrace: [ "/app/foo.rb:1" ]

    _request, payload = capture_request(group, occurrence)

    assert_equal "pb-123", payload["playbook_id"]
    assert_equal "Fix: StandardError in OrdersController#create", payload["title"]
  end

  test "title falls back to job_class then unknown" do
    group = create_error_group job_class: "ImportJob"
    occurrence = group.occurrences.create! backtrace: [ "/app/foo.rb:1" ]

    _request, payload = capture_request(group, occurrence)
    assert_equal "Fix: StandardError in ImportJob", payload["title"]

    group2 = create_error_group
    occurrence2 = group2.occurrences.create! backtrace: [ "/app/foo.rb:1" ]

    _request2, payload2 = capture_request(group2, occurrence2)
    assert_equal "Fix: StandardError in unknown", payload2["title"]
  end

  test "prompt includes required error fields" do
    group = create_error_group
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
    group = create_error_group message: long_message
    occurrence = group.occurrences.create! backtrace: [ "/app/foo.rb:1" ]

    _request, payload = capture_request(group, occurrence)

    assert_not_includes payload["prompt"], long_message
    assert_includes payload["prompt"], "x" * 497 + "..."
  end

  test "prompt includes backtrace limited to 5 frames" do
    backtrace = (1..10).map { |i| "/app/file#{i}.rb:#{i}" }
    group = create_error_group
    occurrence = group.occurrences.create! backtrace:, git_sha: "abc123"

    _request, payload = capture_request(group, occurrence)

    assert_includes payload["prompt"], "/app/file5.rb:5"
    assert_not_includes payload["prompt"], "/app/file6.rb:6"
  end

  test "handles nil occurrence gracefully" do
    group = create_error_group

    _request, payload = capture_request(group, nil)

    assert_includes payload["prompt"], "StandardError"
    assert_not_includes payload["prompt"], "Git SHA"
    assert_not_includes payload["prompt"], "Backtrace"
  end

  # HTTP error handling

  test "raises on non-2xx response" do
    group = create_error_group
    occurrence = group.occurrences.create! backtrace: [ "/app/foo.rb:1" ]

    stub_http_api response_class: Net::HTTPUnauthorized, code: "401", body: "Invalid API key"

    error = assert_raises(RailsInformant::NotifierError) { @notifier.notify group, occurrence }
    assert_includes error.message, "Devin API error: HTTP 401"
    assert_includes error.message, "Invalid API key"
  end

  test "raises on server error" do
    group = create_error_group
    occurrence = group.occurrences.create! backtrace: [ "/app/foo.rb:1" ]

    stub_http_api response_class: Net::HTTPInternalServerError, code: "500", body: ""

    assert_raises(RailsInformant::NotifierError) { @notifier.notify group, occurrence }
  end

  # HTTP timeouts

  test "sets HTTP timeouts" do
    group = create_error_group
    occurrence = group.occurrences.create! backtrace: [ "/app/foo.rb:1" ]

    captured_kwargs = {}
    response = Net::HTTPOK.new("1.1", "200", "")
    response.stubs(:body).returns('{"session_id":"s-123"}')
    stub_http = StubHTTP.new(response)

    Net::HTTP.stubs(:start).with { |_host, _port, **kwargs|
      captured_kwargs = kwargs
      true
    }.yields(stub_http).returns(response)

    @notifier.notify group, occurrence

    assert_equal 10, captured_kwargs[:open_timeout]
    assert_equal 15, captured_kwargs[:read_timeout]
    assert_equal true, captured_kwargs[:use_ssl]
  end

  # NotifyJob integration

  test "NotifyJob includes Devin notifier when configured" do
    group = create_error_group
    group.occurrences.create! backtrace: [ "/app/foo.rb:1" ]

    stub_http_api body: '{"session_id":"s-123"}'

    assert_nothing_raised { RailsInformant::NotifyJob.perform_now group }
  end

  test "NotifyJob skips Devin when api_key missing" do
    RailsInformant.config.devin_api_key = nil
    group = create_error_group
    group.occurrences.create! backtrace: [ "/app/foo.rb:1" ]

    Net::HTTP.expects(:start).never

    RailsInformant::NotifyJob.perform_now group
  end

  test "NotifyJob skips Devin when playbook_id missing" do
    RailsInformant.config.devin_playbook_id = nil
    group = create_error_group
    group.occurrences.create! backtrace: [ "/app/foo.rb:1" ]

    Net::HTTP.expects(:start).never

    RailsInformant::NotifyJob.perform_now group
  end

  private

    def capture_request(group, occurrence)
      stub_http = stub_http_api body: '{"session_id":"s-123"}'
      @notifier.notify group, occurrence
      request = stub_http.captured_request
      payload = JSON.parse(request.body)
      [ request, payload ]
    end
end
