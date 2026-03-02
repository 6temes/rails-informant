require "test_helper"

class RailsInformant::BreadcrumbSubscriberTest < ActiveSupport::TestCase
  test "subscribes to all expected events" do
    expected = RailsInformant::BreadcrumbSubscriber::SUBSCRIPTIONS.keys
    assert expected.include?("sql.active_record")
    assert expected.include?("process_action.action_controller")
    assert expected.include?("perform.active_job")
  end

  test "subscriptions only include allowed keys" do
    allowed = RailsInformant::BreadcrumbSubscriber::SUBSCRIPTIONS["sql.active_record"]
    assert_equal [ :name ], allowed
  end

  test "subscribe! subscribes to all events in SUBSCRIPTIONS" do
    subscribed_events = []
    ActiveSupport::Notifications.stubs(:subscribe).with { |event_name| subscribed_events << event_name; true }

    RailsInformant::BreadcrumbSubscriber.subscribe!

    assert_equal RailsInformant::BreadcrumbSubscriber::SUBSCRIPTIONS.keys, subscribed_events
  ensure
    ActiveSupport::Notifications.unstub(:subscribe)
  end

  test "skips cached SQL queries" do
    RailsInformant.stubs(:initialized?).returns(true)
    RailsInformant::BreadcrumbBuffer.current.flush

    ActiveSupport::Notifications.instrument("sql.active_record", name: "User Load", cached: true) do
      # simulated cached query
    end

    assert_equal 0, RailsInformant::BreadcrumbBuffer.current.flush.size, "Cached SQL queries should be filtered out"
  ensure
    RailsInformant.unstub(:initialized?)
  end

  test "skips SCHEMA SQL queries" do
    RailsInformant.stubs(:initialized?).returns(true)
    RailsInformant::BreadcrumbBuffer.current.flush

    ActiveSupport::Notifications.instrument("sql.active_record", name: "SCHEMA") do
      # simulated schema query
    end

    assert_equal 0, RailsInformant::BreadcrumbBuffer.current.flush.size, "SCHEMA SQL queries should be filtered out"
  ensure
    RailsInformant.unstub(:initialized?)
  end

  test "filters breadcrumb metadata through ContextFilter" do
    RailsInformant.stubs(:initialized?).returns(true)
    RailsInformant::BreadcrumbBuffer.current.flush

    # Stub ContextFilter.filter to return a tagged hash, proving the
    # breadcrumb subscriber routes metadata through it.
    RailsInformant::ContextFilter.stubs(:filter).returns({ _filtered: true })

    ActiveSupport::Notifications.instrument(
      "redirect_to.action_controller",
      status: 302,
      location: "https://example.com/reset?token=secret"
    ) do
      # simulated redirect
    end

    breadcrumbs = RailsInformant::BreadcrumbBuffer.current.flush
    redirect = breadcrumbs.find { it[:category] == "redirect_to.action_controller" }
    assert redirect, "Redirect breadcrumb should be recorded"
    assert_equal({ _filtered: true }, redirect[:metadata])
  ensure
    RailsInformant.unstub(:initialized?)
    RailsInformant::ContextFilter.unstub(:filter)
  end

  test "filters sensitive query parameters in redirect URLs" do
    RailsInformant.stubs(:initialized?).returns(true)
    RailsInformant::BreadcrumbBuffer.current.flush

    ActiveSupport::Notifications.instrument(
      "redirect_to.action_controller",
      status: 302,
      location: "https://example.com/reset?password=abc123&name=test"
    ) do
      # simulated redirect with sensitive query params
    end

    breadcrumbs = RailsInformant::BreadcrumbBuffer.current.flush
    redirect = breadcrumbs.find { it[:category] == "redirect_to.action_controller" }
    assert redirect, "Redirect breadcrumb should be recorded"

    uri = URI.parse(redirect[:metadata][:location])
    params = Rack::Utils.parse_query(uri.query)
    assert_equal "[FILTERED]", params["password"], "Sensitive query params in redirect URL should be filtered"
    assert_equal "test", params["name"], "Non-sensitive query params should be preserved"
  ensure
    RailsInformant.unstub(:initialized?)
  end

  test "records normal SQL queries" do
    RailsInformant.stubs(:initialized?).returns(true)
    RailsInformant::BreadcrumbBuffer.current.flush

    ActiveSupport::Notifications.instrument("sql.active_record", name: "User Load") do
      # simulated normal query
    end

    breadcrumbs = RailsInformant::BreadcrumbBuffer.current.flush
    assert breadcrumbs.size >= 1, "Normal SQL queries should be recorded"
    assert breadcrumbs.any? { it[:category] == "sql.active_record" }
  ensure
    RailsInformant.unstub(:initialized?)
  end
end
