require "test_helper"
require_relative "../support/javascript_asset_stubs"

class RailsInformant::BrowserReportTest < ActiveSupport::TestCase
  include JavascriptAssetStubs

  CART = "https://shop.example/assets/controllers/cart_controller-3a1b2c4d.js"

  setup { stub_javascript_assets }

  test "an allowlisted name keeps its JS prefix and anything else becomes JS::Error" do
    assert_equal "JS::TypeError", build("name" => "TypeError").error_class
    assert_equal "JS::Error", build("name" => "Foo Bar!").error_class
    assert_equal "JS::Error", build("name" => "lowercase").error_class
    assert_equal "JS::Error", build("name" => "A#{"b" * 64}").error_class
    assert_equal "JS::Error", build("name" => { "x" => 1 }).error_class
  end

  test "group attributes describe the page error, not the ingest request" do
    attrs = build.group_attributes(now: Time.current)

    assert_equal "browser", attrs[:source]
    assert_nil attrs[:controller_action]
    assert_nil attrs[:job_class]
    assert_equal "error", attrs[:severity]
    assert_equal "Cannot read properties of null (reading 'value')", attrs[:message]
    assert_equal "app/javascript/controllers/cart_controller.js:42:15:in 'connect'", attrs[:first_backtrace_line]
  end

  test "the message is capped at 1,000 characters and the first backtrace line at 255" do
    long_path = "https://shop.example/#{"x" * 300}.js"
    report = build("message" => "m" * 5_000, "stack" => "go@#{long_path}:1:1")

    assert_equal 1_000, report.message.length
    assert_equal 255, report.group_attributes(now: Time.current)[:first_backtrace_line].length
  end

  test "the backtrace drops the V8 header line and keeps the mapped frames" do
    report = build("stack" => "TypeError: Cannot read properties of null (reading 'value')\n    at CartController.connect (#{CART}:42:15)")

    assert_equal [ "app/javascript/controllers/cart_controller.js:42:15:in 'connect'" ], report.error.backtrace
    assert_equal "Cannot read properties of null (reading 'value')", report.error.message
    assert_equal "TypeError", report.error.name
  end

  test "occurrence attributes come from the report and the verified context" do
    context = RailsInformant::BrowserReport::Context.new(
      rendered_at: 1.minute.ago, request_id: "req-render", revision: "abc1234", user_context: { "id" => 7, "class" => "User" }
    )
    attrs = build(context:).occurrence_attributes

    assert_equal [ "app/javascript/controllers/cart_controller.js:42:15:in 'connect'" ], attrs[:backtrace]
    assert_equal({ ip: "198.51.100.4", url: "https://shop.example/cart?password=%5BFILTERED%5D&step=2", user_agent: "Mozilla/5.0" }, attrs[:request_context])
    assert_equal({ "id" => 7, "class" => "User" }, attrs[:user_context])
    assert_equal "abc1234", attrs[:git_sha]
    assert_equal "req-render", attrs[:request_id]
    assert_equal "req-failing", attrs[:failing_request_id]
    assert_equal Rails.env.to_s, attrs[:environment_context][:rails_env]
  end

  test "without a verified context the occurrence has no user, revision or rendering request" do
    attrs = build.occurrence_attributes

    assert_nil attrs[:user_context]
    assert_nil attrs[:git_sha]
    assert_nil attrs[:request_id]
  end

  test "breadcrumbs keep only the allowlisted keys, are filtered and capped at 20" do
    crumbs = Array.new(25) { |i| { "category" => "ui.click", "message" => "button", "metadata" => { "password" => "hunter2", "id" => "buy-#{i}" }, "timestamp" => "2026-11-01T10:00:00.000Z", "evil" => "x" } }
    stored = build("breadcrumbs" => crumbs + [ "not a hash" ]).occurrence_attributes[:breadcrumbs]

    assert_equal 20, stored.size
    assert_equal({ "category" => "ui.click", "message" => "button", "metadata" => { "password" => "[FILTERED]", "id" => "buy-0" }, "timestamp" => "2026-11-01T10:00:00.000Z" }, stored.first)
  end

  test "the page path is read from the report URL" do
    assert_equal "/cart", build.page_path
    assert_nil build("url" => nil).page_path
  end

  test "navigation and failed-request breadcrumbs have secret query parameters filtered" do
    crumbs = [
      { "category" => "turbo.visit", "message" => "/password/edit?secret=abc&step=2" },
      { "category" => "fetch.error", "message" => "/api/cart?password=hunter2" },
      { "category" => "ui.click", "message" => "button#buy?secret=keep" }
    ]
    stored = build("breadcrumbs" => crumbs).occurrence_attributes[:breadcrumbs].pluck("message")

    assert_equal [ "/password/edit?secret=%5BFILTERED%5D&step=2", "/api/cart?password=%5BFILTERED%5D", "button#buy?secret=keep" ], stored
  end

  test "the stored page URL drops its fragment, where sign-in flows put tokens" do
    url = build("url" => "https://shop.example/callback?page=2#access_token=secret").occurrence_attributes[:request_context][:url]

    assert_equal "https://shop.example/callback?page=2", url
  end

  test "an oversized stack is capped in length and per line before it is stored" do
    report = build("stack" => "TypeError: x\n    at #{"a" * 100_000} (#{CART}:42:15)\n" * 3)

    assert report.occurrence_attributes[:backtrace].all? { it.length <= RailsInformant::BrowserReport::MAX_BACKTRACE_LINE_LENGTH }
    assert_operator report.occurrence_attributes[:backtrace].sum(&:length), :<=, RailsInformant::BrowserReport::MAX_STACK_LENGTH
  end

  test "reports with no first-party frame are silenced as third-party" do
    {
      "iOS injected script" => { "name" => "RangeError", "message" => "Maximum call stack size exceeded.", "stack" => "@\nzk@\nxk@\n@\nzk@\nxk@" },
      "minified injected script" => { "name" => "Error", "message" => "ra", "stack" => "uh@\nGi@\n@" },
      "wallet setter on line 1 of the page" => { "stack" => "@https://shop.example/cart:1:16" },
      "extension error with no stack" => { "name" => "Error", "message" => "Invalid call to runtime.sendMessage(). Tab not found.", "stack" => "" },
      "extension frame" => { "stack" => "    at go (chrome-extension://abcdefghijklmnop/content.js:1:100)" },
      "app inline script on line 1 after a Turbo visit" => { "stack" => "@https://shop.example/checkout:1:5", "url" => "https://shop.example/checkout" }
    }.each do |label, overrides|
      attrs = build(**overrides).group_attributes(now: Time.current)

      assert_equal "ignored", attrs[:status], label
      assert_equal RailsInformant::BrowserReport::THIRD_PARTY_NOTES, attrs[:notes], label
    end
  end

  test "a page frame on line 1 is matched by path with the query ignored" do
    assert_equal RailsInformant::BrowserReport::THIRD_PARTY, build("stack" => "@https://shop.example/cart?step=1:1:16").silenced_reason
  end

  test "a line-1 frame on a page visited earlier in the session is a page frame" do
    report = build(
      "breadcrumbs" => [ { "category" => "turbo.visit", "message" => "/cart?step=2" } ],
      "stack" => "@https://shop.example/cart:1:16",
      "url" => "https://shop.example/checkout"
    )

    assert_equal RailsInformant::BrowserReport::THIRD_PARTY, report.silenced_reason
  end

  test "AbortError is silenced whatever its frames say" do
    turbo = build("name" => "AbortError", "message" => "Fetch is aborted", "stack" => "abort@[native code]\n@https://shop.example/assets/turbo.min-4e5f6a7b.js:1:500")
    app = build("name" => "AbortError", "message" => "Fetch is aborted")

    [ turbo, app ].each do |report|
      attrs = report.group_attributes(now: Time.current)
      assert_equal "ignored", attrs[:status]
      assert_equal RailsInformant::BrowserReport::ABORTED_FETCH_NOTES, attrs[:notes]
      assert_includes attrs[:notes], "AbortError"
    end
  end

  test "a rejection with no reason is silenced, and one with a reason is not" do
    reasonless = build("kind" => "rejection", "name" => "Error", "message" => "undefined", "stack" => "")
    attrs = reasonless.group_attributes(now: Time.current)

    assert_equal "ignored", attrs[:status]
    assert_equal RailsInformant::BrowserReport::REASONLESS_REJECTION_NOTES, attrs[:notes]

    {
      "rejection with a string reason" => { "kind" => "rejection", "name" => "Error", "message" => "checkout failed", "stack" => "" },
      "rejection with an Error that has an app frame" => { "kind" => "rejection", "name" => "Error", "message" => "undefined" },
      "rejection with a TypeError reason" => { "kind" => "rejection", "name" => "TypeError", "message" => "undefined", "stack" => "" }
    }.each do |label, overrides|
      assert_nil build(**overrides).silenced_reason, label
    end
  end

  test "first-party reports are not silenced and carry no status or notes" do
    {
      "app controller" => {},
      "inline script on real page lines" => { "name" => "Error", "message" => "Na", "stack" => "@https://shop.example/cart:519:344\n@https://shop.example/cart:198:221\n@https://shop.example/cart:199:338" },
      "frame-missing Turbo error" => { "kind" => "turbo", "name" => "TurboFrameMissingError", "stack" => "" },
      "rejection of a non-Error value" => { "kind" => "rejection", "name" => "Error", "message" => "[object Object]", "stack" => "" },
      "Chrome syntax error with only the header line" => { "name" => "SyntaxError", "message" => "Unexpected token '}'", "stack" => "SyntaxError: Unexpected token '}'" },
      "vendored pin" => { "stack" => "draw@https://shop.example/assets/chart-1a2b3c4d.js:9:1" },
      "bundle outside the assets prefix" => { "stack" => "@https://shop.example/vite/assets/app-abc123.js:1:4521" },
      "no kind with an app frame" => { "kind" => nil }
    }.each do |label, overrides|
      report = build(**overrides)
      attrs = report.group_attributes(now: Time.current)

      assert_nil report.silenced_reason, label
      assert_not attrs.key?(:status), label
      assert_not attrs.key?(:notes), label
    end
  end

  private

  def build(context: nil, **overrides)
    report = {
      "breadcrumbs" => [],
      "failing_request_id" => "req-failing",
      "kind" => "error",
      "message" => "Cannot read properties of null (reading 'value')",
      "name" => "TypeError",
      "stack" => "TypeError: Cannot read properties of null (reading 'value')\n    at CartController.connect (#{CART}:42:15)",
      "url" => "https://shop.example/cart?password=hunter2&step=2"
    }.merge(overrides)
    RailsInformant::BrowserReport.new report, context:, base_url: ORIGIN, remote_ip: "198.51.100.4", user_agent: "Mozilla/5.0"
  end
end
