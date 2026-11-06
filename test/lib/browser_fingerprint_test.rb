require "test_helper"
require_relative "../support/javascript_asset_stubs"

class RailsInformant::BrowserFingerprintTest < ActiveSupport::TestCase
  include JavascriptAssetStubs

  CART = "https://shop.example/assets/controllers/cart_controller-3a1b2c4d.js"

  setup { stub_javascript_assets }

  test "the same throw in a named method fingerprints identically in Chrome, Firefox and Safari" do
    chrome = fingerprint "Cannot read properties of null (reading 'value')", <<~STACK
      TypeError: Cannot read properties of null (reading 'value')
          at CartController.connect (#{CART}:42:15)
    STACK
    firefox = fingerprint "can't access property \"value\", el is null", "connect@#{CART}:42:15"
    safari = fingerprint "null is not an object (evaluating 'el.value')", "connect@#{CART}:42:20"

    assert_equal chrome, firefox
    assert_equal chrome, safari
  end

  test "the same throw in a nested anonymous callback fingerprints identically in Chrome, Firefox and Safari" do
    chrome = fingerprint "boom", <<~STACK
      TypeError: boom
          at HTMLButtonElement.<anonymous> (#{CART}:50:7)
          at CartController.connect (#{CART}:42:15)
    STACK
    firefox = fingerprint "boom", "connect/<@#{CART}:50:7\nconnect@#{CART}:42:15"
    safari = fingerprint "boom", "@#{CART}:50:9\nconnect@#{CART}:42:15"

    assert_equal chrome, firefox
    assert_equal chrome, safari
    assert_not_equal chrome, fingerprint("boom", "connect@#{CART}:42:15")
  end

  test "asset digest, host, line and column do not change the fingerprint" do
    before = fingerprint "boom", "    at CartController.connect (#{CART}:42:15)"
    after = fingerprint "boom", "    at CartController.connect (https://shop.example/assets/controllers/cart_controller-9e8f7a6b.js:45:3)"

    assert_equal before, after
  end

  test "the error name separates groups that share a frame" do
    assert_not_equal fingerprint("boom", "connect@#{CART}:42:15", error_class: "JS::TypeError"),
      fingerprint("boom", "connect@#{CART}:42:15", error_class: "JS::RangeError")
  end

  test "vendored frames are skipped in favour of the first app frame" do
    with_vendor = fingerprint "boom", "draw@https://shop.example/assets/chart-1a2b3c4d.js:9:1\nconnect@#{CART}:42:15"

    assert_equal fingerprint("boom", "connect@#{CART}:42:15"), with_vendor
  end

  test "frameless reports group on the message with UUIDs, URLs, hex and digits replaced" do
    first = fingerprint "Failed to load 3f2b8c1e-4a5d-4e6f-9a7b-1c2d3e4f5a6b from https://cdn.example/a.js?v=1 after 3 tries (0xdeadbeef42)", ""
    second = fingerprint "Failed to load 9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d from https://cdn.example/b.js after 12 tries (0x1234abcd99)", ""

    assert_equal first, second
    assert_not_equal first, fingerprint("Failed to fetch dynamically imported module", "")
  end

  test "a frameless browser TypeError does not share the Ruby TypeError fingerprint" do
    assert_not_equal RailsInformant::Fingerprint.generate(TypeError.new("boom")), fingerprint("boom", "")
  end

  test "a first-party fingerprint keeps its existing format" do
    assert_equal Digest::SHA256.hexdigest("browser:JS::TypeError:app/javascript/controllers/cart_controller.js:connect"),
      fingerprint("boom", "connect@#{CART}:42:15")
  end

  test "a silenced report never shares a group with a first-party report of the same error" do
    silenced = fingerprint("boom 1", "", silenced_reason: RailsInformant::BrowserReport::THIRD_PARTY)

    assert_not_equal fingerprint("boom 1", "@https://shop.example/cart:57:3"), silenced
    assert_equal silenced, fingerprint("boom 2", "", silenced_reason: RailsInformant::BrowserReport::THIRD_PARTY)
  end

  private

  def fingerprint(message, stack, error_class: "JS::TypeError", silenced_reason: nil)
    RailsInformant::BrowserFingerprint.generate error_class:, message:, silenced_reason:,
      stack: RailsInformant::JavascriptStack.parse(stack, origin: ORIGIN)
  end
end
