require "test_helper"

class RailsInformant::BreadcrumbBufferTest < ActiveSupport::TestCase
  test "records breadcrumbs" do
    buffer = RailsInformant::BreadcrumbBuffer.new
    buffer.record category: "sql.active_record", message: "sql", metadata: { name: "User Load" }

    crumbs = buffer.flush
    assert_equal 1, crumbs.size
    assert_equal "sql.active_record", crumbs.first[:category]
    assert_equal "sql", crumbs.first[:message]
    assert_kind_of String, crumbs.first[:timestamp]
    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}/, crumbs.first[:timestamp])
  end

  test "flush clears buffer" do
    buffer = RailsInformant::BreadcrumbBuffer.new
    buffer.record category: "test", message: "test"
    buffer.flush
    assert_equal 0, buffer.flush.size
  end

  test "enforces capacity limit" do
    buffer = RailsInformant::BreadcrumbBuffer.new
    capacity = RailsInformant::BreadcrumbBuffer::CAPACITY

    (capacity + 5).times { |i| buffer.record category: "test", message: "msg-#{i}" }

    crumbs = buffer.flush
    assert_equal capacity, crumbs.size
    assert_equal "msg-5", crumbs.first[:message]
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
