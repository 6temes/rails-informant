require "test_helper"

class RailsInformant::StructuredEventSubscriberTest < ActiveSupport::TestCase
  setup do
    @subscriber = RailsInformant::StructuredEventSubscriber.new
    RailsInformant::BreadcrumbBuffer.current.flush
  end

  test "emit records breadcrumb when initialized" do
    RailsInformant.stubs(:initialized?).returns(true)

    event = { name: "custom.event", payload: { user_id: 1 } }
    @subscriber.emit(event)

    breadcrumbs = RailsInformant::BreadcrumbBuffer.current.flush
    assert_equal 1, breadcrumbs.size
    assert_equal "custom.event", breadcrumbs.first[:category]
    assert_equal "custom.event", breadcrumbs.first[:message]
    assert_nil breadcrumbs.first[:duration]
  ensure
    RailsInformant.unstub(:initialized?)
  end

  test "emit skips when not initialized" do
    RailsInformant.stubs(:initialized?).returns(false)

    @subscriber.emit(name: "custom.event", payload: { user_id: 1 })

    breadcrumbs = RailsInformant::BreadcrumbBuffer.current.flush
    assert_equal 0, breadcrumbs.size
  ensure
    RailsInformant.unstub(:initialized?)
  end

  test "emit filters payload through ContextFilter" do
    RailsInformant.stubs(:initialized?).returns(true)
    RailsInformant::ContextFilter.stubs(:filter).returns({ _filtered: true })

    @subscriber.emit(name: "custom.event", payload: { password: "secret123" })

    breadcrumbs = RailsInformant::BreadcrumbBuffer.current.flush
    assert_equal 1, breadcrumbs.size
    assert_equal({ _filtered: true }, breadcrumbs.first[:metadata])
  ensure
    RailsInformant.unstub(:initialized?)
    RailsInformant::ContextFilter.unstub(:filter)
  end

  test "emit uses empty hash when payload is not a Hash" do
    RailsInformant.stubs(:initialized?).returns(true)

    @subscriber.emit(name: "custom.event", payload: "not a hash")

    breadcrumbs = RailsInformant::BreadcrumbBuffer.current.flush
    assert_equal 1, breadcrumbs.size
    assert_equal({}, breadcrumbs.first[:metadata])
  ensure
    RailsInformant.unstub(:initialized?)
  end
end
