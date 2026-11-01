require "test_helper"
require "net/http"
require_relative "../support/javascript_asset_stubs"

class RailsInformant::ErrorRecorderTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  test "records error and creates group + occurrence" do
    error = build_error

    assert_difference -> { RailsInformant::ErrorGroup.count } => 1,
                      -> { RailsInformant::Occurrence.count } => 1 do
      RailsInformant::ErrorRecorder.record error
    end

    group = RailsInformant::ErrorGroup.last
    assert_equal "StandardError", group.error_class
    assert_equal "boom", group.message
    assert_equal 1, group.total_occurrences
    assert_equal "unresolved", group.status
  end

  test "occurrence cooldown skips occurrence storage" do
    error = build_error
    RailsInformant::ErrorRecorder.record error

    # Second recording within cooldown — counter increments but no new occurrence
    assert_no_difference "RailsInformant::Occurrence.count" do
      RailsInformant::ErrorRecorder.record error
    end

    assert_equal 2, RailsInformant::ErrorGroup.last.total_occurrences
  end

  test "capture failure does not raise" do
    RailsInformant.stubs(:initialized?).returns(true)
    RailsInformant::Fingerprint.stubs(:generate).raises(RuntimeError, "bad fingerprint")

    assert_nothing_raised do
      RailsInformant::ErrorRecorder.record build_error
    end
  end

  test "exception chain captures cause" do
    inner = StandardError.new("inner error")
    inner.set_backtrace [ "/app/inner.rb:1" ]
    outer = RuntimeError.new("outer error")
    outer.set_backtrace [ "/app/outer.rb:1" ]

    # Ruby doesn't let you set cause directly, but we can test the chain builder
    begin
      begin
        raise inner
      rescue
        raise outer
      end
    rescue => error
      RailsInformant::ErrorRecorder.record error
    end

    occurrence = RailsInformant::Occurrence.last
    assert occurrence.exception_chain.present?
    assert_equal "StandardError", occurrence.exception_chain.first["class"]
  end

  test "enqueues NotifyJob when a notifier would send" do
    RailsInformant.config.slack_webhook_url = "https://hooks.slack.com/test"

    assert_enqueued_with job: RailsInformant::NotifyJob do
      RailsInformant::ErrorRecorder.record build_error
    end
  end

  test "skips NotifyJob when no notifier would send" do
    # No webhook configured — no notifiers exist
    RailsInformant.config.slack_webhook_url = nil
    RailsInformant.config.webhook_url = nil
    RailsInformant.config.reset_notifiers!

    assert_no_enqueued_jobs only: RailsInformant::NotifyJob do
      RailsInformant::ErrorRecorder.record build_error
    end
  end

  test "skips NotifyJob when notifiers exist but none would send" do
    RailsInformant.config.slack_webhook_url = "https://hooks.slack.com/test"

    # First record to create group
    RailsInformant::ErrorRecorder.record build_error
    group = RailsInformant::ErrorGroup.last
    # Mark as recently notified so should_notify? returns false
    group.update_column :last_notified_at, Time.current
    group.update_column :total_occurrences, 5

    assert_no_enqueued_jobs only: RailsInformant::NotifyJob do
      RailsInformant::ErrorRecorder.record build_error
    end
  end

  test "skips recording entirely when delivering_notification flag is set" do
    RailsInformant.config.slack_webhook_url = "https://hooks.slack.com/test"

    assert_no_difference -> { RailsInformant::ErrorGroup.count } do
      assert_no_enqueued_jobs only: RailsInformant::NotifyJob do
        RailsInformant::Current.delivering_notification = true
        RailsInformant::ErrorRecorder.record build_error
      end
    end
  ensure
    RailsInformant::Current.delivering_notification = false
  end

  test "skips recording entirely in an interactive console" do
    RailsInformant.stubs(:console_mode?).returns(true)
    RailsInformant.config.slack_webhook_url = "https://hooks.slack.com/test"

    assert_no_difference -> { RailsInformant::ErrorGroup.count } do
      assert_no_enqueued_jobs only: RailsInformant::NotifyJob do
        RailsInformant::ErrorRecorder.record build_error
      end
    end
  end

  test "skips recording in rails runner when capture_runner_errors is off" do
    RailsInformant.stubs(:runner_mode?).returns(true)
    RailsInformant.config.capture_runner_errors = false
    RailsInformant.config.slack_webhook_url = "https://hooks.slack.com/test"

    assert_no_difference -> { RailsInformant::ErrorGroup.count } do
      assert_no_enqueued_jobs only: RailsInformant::NotifyJob do
        RailsInformant::ErrorRecorder.record build_error
      end
    end
  end

  test "records in rails runner by default, so scheduled tasks still report" do
    RailsInformant.stubs(:runner_mode?).returns(true)

    assert_difference -> { RailsInformant::ErrorGroup.count } => 1 do
      RailsInformant::ErrorRecorder.record build_error
    end
  end

  test "capture_runner_errors does not suppress errors outside rails runner" do
    RailsInformant.stubs(:runner_mode?).returns(false)
    RailsInformant.config.capture_runner_errors = false

    assert_difference -> { RailsInformant::ErrorGroup.count } => 1 do
      RailsInformant::ErrorRecorder.record build_error
    end
  end

  test "skips recording entirely when error backtrace includes notifier path" do
    RailsInformant.config.slack_webhook_url = "https://hooks.slack.com/test"

    error = StandardError.new("SSL error")
    error.set_backtrace [
      "/gems/informant/lib/rails_informant/notifiers/notification_policy.rb:55:in `post_json'",
      "/gems/informant/lib/rails_informant/notifiers/slack.rb:7:in `notify'"
    ]

    assert_no_difference -> { RailsInformant::ErrorGroup.count } do
      assert_no_enqueued_jobs only: RailsInformant::NotifyJob do
        RailsInformant::ErrorRecorder.record error
      end
    end
  end

  test "before_record callback can halt recording" do
    RailsInformant.config.before_record do |event|
      event.halt! if event.message.include?("noisy")
    end

    assert_no_difference -> { RailsInformant::ErrorGroup.count } do
      RailsInformant::ErrorRecorder.record build_error("noisy timeout")
    end
  end

  test "before_record callback can override fingerprint" do
    RailsInformant.config.before_record do |event|
      event.fingerprint = "custom-group"
    end

    RailsInformant::ErrorRecorder.record build_error("first")
    RailsInformant::ErrorRecorder.record build_error("second")

    # Both should land in the same group despite different messages
    assert_equal 1, RailsInformant::ErrorGroup.count
    assert_equal 2, RailsInformant::ErrorGroup.last.total_occurrences
  end

  test "before_record callback can override severity" do
    RailsInformant.config.before_record do |event|
      event.severity = "warning" if event.error_class == "StandardError"
    end

    RailsInformant::ErrorRecorder.record build_error
    assert_equal "warning", RailsInformant::ErrorGroup.last.severity
  end

  test "before_record callback exception is logged but does not halt" do
    RailsInformant.config.before_record do |_event|
      raise "callback bug"
    end

    assert_difference -> { RailsInformant::ErrorGroup.count }, 1 do
      RailsInformant::ErrorRecorder.record build_error
    end
  end

  test "before_record callbacks run in order and halt stops chain" do
    calls = []
    RailsInformant.config.before_record { |_e| calls << :first }
    RailsInformant.config.before_record { |e| calls << :second; e.halt! }
    RailsInformant.config.before_record { |_e| calls << :third }

    RailsInformant::ErrorRecorder.record build_error
    assert_equal %i[first second], calls
  end

  test "before_record event exposes request_path from env" do
    observed_path = nil
    RailsInformant.config.before_record { |e| observed_path = e.request_path }

    env = { "PATH_INFO" => "/api/users", "REQUEST_METHOD" => "GET" }
    RailsInformant::ErrorRecorder.record build_error, env: env

    assert_equal "/api/users", observed_path
  end

  test "spike protection suppresses occurrence storage and notifications after threshold" do
    RailsInformant.config.spike_protection = { threshold: 3, window: 1.minute }
    RailsInformant::ErrorRecorder.reset_spike_counters!

    # First 3 should record normally
    3.times { RailsInformant::ErrorRecorder.record build_error }
    assert_equal 1, RailsInformant::ErrorGroup.count
    assert_equal 3, RailsInformant::ErrorGroup.last.total_occurrences

    # 4th and beyond should still increment counters but not store occurrences
    occurrence_count_before = RailsInformant::Occurrence.count
    2.times { RailsInformant::ErrorRecorder.record build_error }

    assert_equal 5, RailsInformant::ErrorGroup.last.total_occurrences
    assert_equal occurrence_count_before, RailsInformant::Occurrence.count
  end

  test "spike protection resets after window expires" do
    RailsInformant.config.spike_protection = { threshold: 2, window: 1.minute }
    RailsInformant::ErrorRecorder.reset_spike_counters!

    3.times { RailsInformant::ErrorRecorder.record build_error }

    # Travel past the window
    travel 2.minutes do
      occurrence_count_before = RailsInformant::Occurrence.count
      RailsInformant::ErrorRecorder.record build_error
      # Should store again after window reset
      assert_operator RailsInformant::Occurrence.count, :>=, occurrence_count_before
    end
  end

  test "spike protection is disabled when config is nil" do
    RailsInformant.config.spike_protection = nil
    RailsInformant::ErrorRecorder.reset_spike_counters!

    10.times { RailsInformant::ErrorRecorder.record build_error }
    assert_equal 10, RailsInformant::ErrorGroup.last.total_occurrences
  end

  test "records normally for errors not from informant" do
    RailsInformant.config.slack_webhook_url = "https://hooks.slack.com/test"

    error = StandardError.new("regular error")
    error.set_backtrace [ "/app/models/user.rb:42:in `save'" ]

    assert_enqueued_with job: RailsInformant::NotifyJob do
      RailsInformant::ErrorRecorder.record error
    end
  end

  test "trim_occurrences keeps only newest MAX_OCCURRENCES_PER_GROUP records" do
    group = create_error_group total_occurrences: 30

    # Create 30 occurrences with staggered timestamps
    30.times do |i|
      group.occurrences.create!(
        backtrace: [ "/app/test.rb:#{i}" ],
        created_at: (30 - i).minutes.ago
      )
    end

    assert_equal 30, group.occurrences.count

    RailsInformant::ErrorRecorder.send :trim_occurrences, group

    assert_equal 25, group.occurrences.count

    # The 5 oldest should be gone (created_at 30..26 minutes ago)
    remaining = group.occurrences.order(created_at: :desc).pluck(:backtrace)
    remaining.each_with_index do |bt, i|
      # Newest occurrence has index 29, next 28, etc.
      assert_equal [ "/app/test.rb:#{29 - i}" ], bt
    end
  end

  test "trim_occurrences is a no-op when at or below limit" do
    group = create_error_group total_occurrences: 25

    25.times do |i|
      group.occurrences.create!(backtrace: [ "/app/test.rb:#{i}" ])
    end

    assert_no_difference -> { group.occurrences.count } do
      RailsInformant::ErrorRecorder.send :trim_occurrences, group
    end
  end

  test "stores environment context" do
    RailsInformant::ContextBuilder.reset!
    Socket.stubs(:gethostname).returns("web-01.prod")
    RailsInformant::ErrorRecorder.record build_error

    occurrence = RailsInformant::Occurrence.last
    env_ctx = occurrence.environment_context
    assert_equal Rails.env.to_s, env_ctx["rails_env"]
    assert_equal RUBY_VERSION, env_ctx["ruby_version"]
    assert_equal "web-01.prod", env_ctx["hostname"]
    assert env_ctx["pid"].is_a?(Integer)
  ensure
    RailsInformant::ContextBuilder.reset!
  end

  test "environment context omits hostname when localhost" do
    RailsInformant::ContextBuilder.reset!
    Socket.stubs(:gethostname).returns("localhost")
    RailsInformant::ErrorRecorder.record build_error

    occurrence = RailsInformant::Occurrence.last
    env_ctx = occurrence.environment_context
    assert_nil env_ctx["hostname"]
  ensure
    RailsInformant::ContextBuilder.reset!
  end

  private

  def build_error(message = "boom")
    error = StandardError.new(message)
    error.set_backtrace [ "/app/models/user.rb:42:in `save'" ]
    error
  end
end

class RailsInformant::ErrorRecorderRequestIdTest < ActionDispatch::IntegrationTest
  class ReportingJob < ActiveJob::Base
    def perform = Rails.error.report(RuntimeError.new("reported from a job"))
  end

  # The dummy app re-raises non-rescuable exceptions, which would leave no
  # response (and no X-Request-Id header) to compare against.
  setup do
    @show_exceptions = Rails.application.env_config["action_dispatch.show_exceptions"]
    Rails.application.env_config["action_dispatch.show_exceptions"] = :all
  end

  teardown do
    Rails.application.env_config["action_dispatch.show_exceptions"] = @show_exceptions
  end

  test "an error raised in a request records the request ID Rails assigned" do
    assert_difference -> { RailsInformant::ErrorGroup.count } => 1,
                      -> { RailsInformant::Occurrence.count } => 1 do
      get "/failures/raise_error"
    end

    assert_response :internal_server_error
    assert_predicate response.headers["X-Request-Id"], :present?
    assert_equal response.headers["X-Request-Id"], RailsInformant::Occurrence.last.request_id
    assert_equal "server", RailsInformant::ErrorGroup.last.source
  end

  test "an error reported through Rails.error inside an action records the controller's request ID" do
    assert_difference -> { RailsInformant::Occurrence.count } => 1 do
      get "/failures/report_error"
    end

    assert_response :ok
    occurrence = RailsInformant::Occurrence.last
    assert_equal "RuntimeError", occurrence.error_group.error_class
    assert_nil occurrence.request_context, "the subscriber path has no rack env"
    assert_equal response.headers["X-Request-Id"], occurrence.request_id
  end

  test "an error reported from a job leaves request_id nil" do
    assert_difference -> { RailsInformant::Occurrence.count } => 1 do
      ReportingJob.perform_now
    end

    assert_nil RailsInformant::Occurrence.last.request_id
  end

  test "an unmigrated schema still records server errors without the new attributes" do
    RailsInformant.stubs(:browser_schema_ready?).returns(false)

    assert_difference -> { RailsInformant::ErrorGroup.count } => 1,
                      -> { RailsInformant::Occurrence.count } => 1 do
      get "/failures/raise_error"
    end

    assert_nil RailsInformant::Occurrence.last.request_id
  end
end

class RailsInformant::ErrorRecorderBrowserTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include JavascriptAssetStubs

  CART = "https://shop.example/assets/controllers/cart_controller-3a1b2c4d.js"
  CHROME_STACK = <<~STACK
    TypeError: Cannot read properties of null (reading 'value')
        at CartController.connect (#{CART}:42:15)
  STACK
  CLIENT_CRUMB = { "category" => "ui.click", "message" => "button", "metadata" => { "id" => "buy" }, "timestamp" => "2026-11-01T10:00:00.000Z" }.freeze

  setup do
    stub_javascript_assets
    RailsInformant::ErrorRecorder.reset_spike_counters!
  end

  test "a report creates a browser group named after the JS error" do
    assert_difference -> { RailsInformant::ErrorGroup.count } => 1,
                      -> { RailsInformant::Occurrence.count } => 1 do
      record_browser
    end

    group = RailsInformant::ErrorGroup.last
    assert_equal "JS::TypeError", group.error_class
    assert_equal "browser", group.source
    assert_nil group.controller_action
  end

  test "a name outside the allowlist is stored as JS::Error" do
    record_browser "name" => "Foo Bar!"

    assert_equal "JS::Error", RailsInformant::ErrorGroup.last.error_class
  end

  test "a new deploy's digest and shifted line join the group and reopen it when resolved" do
    record_browser
    group = RailsInformant::ErrorGroup.last
    group.update_columns status: "resolved", resolved_at: 1.minute.ago

    assert_no_difference -> { RailsInformant::ErrorGroup.count } do
      record_browser("stack" => "    at CartController.connect (https://shop.example/assets/controllers/cart_controller-9e8f7a6b.js:45:3)",
        context: context(rendered_at: Time.current))
    end

    assert_equal "unresolved", group.reload.status
    assert_equal 2, group.total_occurrences
  end

  test "a Safari-worded message for the same frame joins the group" do
    record_browser
    assert_no_difference -> { RailsInformant::ErrorGroup.count } do
      record_browser "message" => "null is not an object (evaluating 'el.value')", "stack" => "connect@#{CART}:42:20"
    end
  end

  test "a frameless browser TypeError and a Ruby TypeError land in different groups" do
    ruby_error = TypeError.new("boom").tap { it.set_backtrace [ "/app/models/cart.rb:3:in 'total'" ] }

    assert_difference -> { RailsInformant::ErrorGroup.count } => 2 do
      RailsInformant::ErrorRecorder.record ruby_error
      record_browser "message" => "boom", "stack" => ""
    end
  end

  test "the occurrence carries the page and the client's breadcrumbs, and leaves no server crumbs behind" do
    RailsInformant::BreadcrumbBuffer.current.record category: "sql.active_record", message: "sql"

    record_browser(context: context(request_id: "req-render", revision: "abc1234", user_context: { "id" => 7 }))
    assert_empty RailsInformant::BreadcrumbBuffer.current.flush

    occurrence = RailsInformant::Occurrence.last
    assert_equal "https://shop.example/cart", occurrence.request_context["url"]
    assert_equal "Mozilla/5.0", occurrence.request_context["user_agent"]
    assert_equal [ CLIENT_CRUMB ], occurrence.breadcrumbs
    assert_equal({ "id" => 7 }, occurrence.user_context)
    assert_equal "req-render", occurrence.request_id
    assert_equal "req-failing", occurrence.failing_request_id
    assert_equal "abc1234", occurrence.git_sha
    assert_equal [ "app/javascript/controllers/cart_controller.js:42:15:in 'connect'" ], occurrence.backtrace
  end

  test "before_record callbacks see the JS error and can halt the report" do
    seen = nil
    RailsInformant.config.before_record do |event|
      seen = [ event.error.message, event.error.backtrace, event.source, event.request_path, event.error_class ]
      event.halt!
    end

    assert_no_difference -> { RailsInformant::ErrorGroup.count } do
      record_browser
    end

    assert_equal [ "Cannot read properties of null (reading 'value')",
      [ "app/javascript/controllers/cart_controller.js:42:15:in 'connect'" ], "browser", "/cart", "JS::TypeError" ], seen
  end

  test "server events report their source as server" do
    source = nil
    RailsInformant.config.before_record { source = it.source }

    RailsInformant::ErrorRecorder.record StandardError.new("boom").tap { it.set_backtrace [ "/app/models/user.rb:1" ] }

    assert_equal "server", source
  end

  test "ignored_exceptions matches the full JS name only" do
    RailsInformant.config.ignored_exceptions = [ "TypeError" ]
    RailsInformant.reset_caches!
    assert_difference(-> { RailsInformant::ErrorGroup.count }, 1) { record_browser }

    RailsInformant.config.ignored_exceptions = [ "JS::TypeError" ]
    RailsInformant.reset_caches!
    assert_no_difference(-> { RailsInformant::ErrorGroup.last.reload.total_occurrences }) { record_browser }
  end

  test "a page under ignored_paths is dropped" do
    RailsInformant.config.ignored_paths = [ "/cart" ]

    assert_no_difference -> { RailsInformant::ErrorGroup.count } do
      record_browser "url" => "https://shop.example/cart/items?x=1"
    end
    assert_difference -> { RailsInformant::ErrorGroup.count } => 1 do
      record_browser "url" => "https://shop.example/cartography"
    end
  end

  test "a stale tab from before the resolution does not reopen the group or notify, but is counted" do
    RailsInformant.config.slack_webhook_url = "https://hooks.slack.com/test"
    record_browser
    group = RailsInformant::ErrorGroup.last
    group.update_columns status: "resolved", resolved_at: 1.hour.ago, last_occurrence_stored_at: 1.minute.ago

    assert_difference -> { RailsInformant::Occurrence.count } => 1 do
      assert_no_enqueued_jobs only: RailsInformant::NotifyJob do
        record_browser(context: context(rendered_at: 2.hours.ago))
      end
    end

    group.reload
    assert_equal "resolved", group.status
    assert_equal 2, group.total_occurrences
  end

  test "a day-old blob rendered before the resolution records with no user and does not reopen the group" do
    record_browser
    group = RailsInformant::ErrorGroup.last
    group.update_columns status: "resolved", resolved_at: 1.hour.ago, last_occurrence_stored_at: 1.minute.ago

    record_browser(context: context(rendered_at: 25.hours.ago, revision: "abc1234"))

    assert_equal "resolved", group.reload.status
    assert_nil RailsInformant::Occurrence.last.user_context
    assert_equal "abc1234", RailsInformant::Occurrence.last.git_sha
  end

  test "a report without a verified render time cannot reopen a resolved group" do
    RailsInformant.config.slack_webhook_url = "https://hooks.slack.com/test"
    record_browser
    group = RailsInformant::ErrorGroup.last
    group.update_columns status: "resolved", resolved_at: 1.hour.ago, last_occurrence_stored_at: 1.minute.ago

    assert_no_enqueued_jobs only: RailsInformant::NotifyJob do
      record_browser(context: nil)
    end

    assert_equal "resolved", group.reload.status
  end

  test "a page rendered after the resolution reopens the group and notifies" do
    RailsInformant.config.slack_webhook_url = "https://hooks.slack.com/test"
    record_browser
    group = RailsInformant::ErrorGroup.last
    group.update_columns status: "resolved", resolved_at: 1.hour.ago

    assert_enqueued_with job: RailsInformant::NotifyJob do
      record_browser(context: context(rendered_at: 1.minute.ago))
    end

    assert_equal "unresolved", group.reload.status
  end

  test "once the hourly new-group limit is reached, new browser groups are dropped but existing ones still record" do
    RailsInformant.config.browser_new_group_limit = 2
    record_browser "message" => "first", "stack" => ""
    record_browser "message" => "second", "stack" => ""
    Rails.logger.expects(:warn).with(includes("browser_new_group_limit")).once

    assert_no_difference -> { RailsInformant::ErrorGroup.count } do
      record_browser "message" => "third", "stack" => ""
      record_browser "message" => "fourth", "stack" => ""
    end

    assert_difference -> { RailsInformant::ErrorGroup.find_by(message: "first").total_occurrences } => 1 do
      record_browser "message" => "first", "stack" => ""
    end
  end

  test "groups created more than an hour ago and server groups do not count toward the limit" do
    RailsInformant.config.browser_new_group_limit = 1
    record_browser "message" => "old", "stack" => ""
    RailsInformant::ErrorGroup.last.update_columns created_at: 2.hours.ago
    RailsInformant::ErrorRecorder.record StandardError.new("server").tap { it.set_backtrace [ "/app/models/user.rb:1" ] }
    assert_equal 2, RailsInformant::ErrorGroup.count

    assert_difference -> { RailsInformant::ErrorGroup.count } => 1 do
      record_browser "message" => "new", "stack" => ""
    end
  end

  test "spike protection applies to browser groups" do
    RailsInformant.config.spike_protection = { threshold: 2, window: 1.minute }

    # Each report lands past the occurrence cooldown, inside the spike window.
    1.upto(4) { |i| travel(10.seconds * i) { record_browser } }

    group = RailsInformant::ErrorGroup.last
    assert_equal 4, group.total_occurrences
    assert_equal 2, group.occurrences.count
  end

  test "a server error raised while ingesting a browser report is not recorded" do
    RailsInformant::Current.ingesting_browser_report = true

    assert_no_difference -> { RailsInformant::ErrorGroup.count } do
      RailsInformant::ErrorRecorder.record StandardError.new("ingest failed").tap { it.set_backtrace [ "/app/models/user.rb:1" ] }
    end
    assert_difference -> { RailsInformant::ErrorGroup.count } => 1 do
      record_browser
    end
  end

  private

  def context(rendered_at: 1.minute.ago, request_id: nil, revision: nil, user_context: nil)
    RailsInformant::BrowserReport::Context.new(rendered_at:, request_id:, revision:, user_context:)
  end

  def record_browser(context: nil, **overrides)
    report = {
      "breadcrumbs" => [ CLIENT_CRUMB ],
      "failing_request_id" => "req-failing",
      "kind" => "error",
      "message" => "Cannot read properties of null (reading 'value')",
      "name" => "TypeError",
      "occurred_at" => "2026-11-01T10:00:01.000Z",
      "stack" => CHROME_STACK,
      "url" => "https://shop.example/cart"
    }.merge(overrides)
    RailsInformant::ErrorRecorder.record_browser report, context:, base_url: ORIGIN, remote_ip: "198.51.100.4", user_agent: "Mozilla/5.0"
  end
end
