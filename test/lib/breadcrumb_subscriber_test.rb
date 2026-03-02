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
end
