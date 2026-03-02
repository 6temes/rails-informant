require "test_helper"

class RailsInformant::BreadcrumbBufferTest < ActiveSupport::TestCase
  test "records breadcrumbs" do
    buffer = RailsInformant::BreadcrumbBuffer.new
    buffer.record category: "sql.active_record", message: "sql", metadata: { name: "User Load" }

    crumbs = buffer.flush
    assert_equal 1, crumbs.size
    assert_equal "sql.active_record", crumbs.first[:category]
    assert_equal "sql", crumbs.first[:message]
    assert crumbs.first[:timestamp].present?
  end

  test "flush clears buffer" do
    buffer = RailsInformant::BreadcrumbBuffer.new
    buffer.record category: "test", message: "test"
    buffer.flush
    assert_equal 0, buffer.size
  end

  test "respects configurable capacity" do
    RailsInformant.config.breadcrumb_capacity = 3
    buffer = RailsInformant::BreadcrumbBuffer.new

    5.times { |i| buffer.record category: "test", message: "msg-#{i}" }

    crumbs = buffer.flush
    assert_equal 3, crumbs.size
    assert_equal "msg-2", crumbs.first[:message]
    assert_equal "msg-4", crumbs.last[:message]
  end

  test "current returns same buffer within request" do
    buf1 = RailsInformant::BreadcrumbBuffer.current
    buf2 = RailsInformant::BreadcrumbBuffer.current
    assert_same buf1, buf2
  end

  test "records duration" do
    buffer = RailsInformant::BreadcrumbBuffer.new
    buffer.record category: "test", message: "test", duration: 42.5
    assert_equal 42.5, buffer.flush.first[:duration]
  end
end
