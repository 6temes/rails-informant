require "test_helper"

class RailsInformant::BrowserHelperTest < ActionView::TestCase
  NONCE = "test-nonce-0123456789"

  # Stands in for a host ApplicationController. Route and mount helpers are
  # added when ActionController::Base is subclassed, and a class defined inside
  # the engine's namespace would get the engine's routes, so it starts anonymous.
  HostController = Class.new ActionController::Base

  test "with browser capture off a host view can call the tag and gets nothing" do
    assert_equal "[]", HostController.render(inline: "[<%= informant_browser_tag %>]")
  end

  test "a host view renders the tag once capture is enabled after boot" do
    RailsInformant.config.capture_browser_errors = true

    html = HostController.render(inline: "<%= informant_browser_tag %>")

    assert_includes html, '<meta name="informant-browser" content="'
    assert_includes html, '<meta name="informant-browser-endpoint" content="/informant/browser_reports">'
    assert_includes html, "import('rails_informant')"
  end

  test "renders the context blob, the endpoint and the early hook carrying the CSP nonce" do
    RailsInformant.config.capture_browser_errors = true
    request.content_security_policy_nonce_generator = ->(_) { NONCE }
    request.request_id = "render-request-1"

    fragment = Nokogiri::HTML5.fragment(render(inline: "<%= informant_browser_tag %>"))

    blob = fragment.at_css('meta[name="informant-browser"]')["content"]
    assert_equal "render-request-1", RailsInformant::BrowserContext.verify(blob).request_id
    assert_equal "/informant/browser_reports", fragment.at_css('meta[name="informant-browser-endpoint"]')["content"]

    script = fragment.at_css("script")
    assert_equal NONCE, script["nonce"]
    assert_includes script.text, "window.__railsInformant = state"
    assert_includes script.text, "import('rails_informant')"
  end

  test "the early hook has no nonce attribute when the request has no CSP nonce" do
    RailsInformant.config.capture_browser_errors = true

    script = Nokogiri::HTML5.fragment(render(inline: "<%= informant_browser_tag %>")).at_css("script")

    assert_not script.key?("nonce")
  end

  test "the endpoint follows the path the host mounts the engine at" do
    RailsInformant.config.capture_browser_errors = true
    Rails.application.routes.draw { mount RailsInformant::Engine => "/ops/errors" }

    html = HostController.render(inline: "<%= informant_browser_tag %>")

    assert_includes html, '<meta name="informant-browser-endpoint" content="/ops/errors/browser_reports">'
  ensure
    Rails.application.reload_routes!
  end
end
