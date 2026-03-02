require "test_helper"

class RailsInformant::ContextFilterTest < ActiveSupport::TestCase
  test "filters sensitive parameters" do
    RailsInformant.config.filter_parameters = [ :password, :secret ]

    result = RailsInformant::ContextFilter.filter(
      password: "hunter2",
      secret: "abc",
      name: "test"
    )

    assert_equal "[FILTERED]", result[:password]
    assert_equal "[FILTERED]", result[:secret]
    assert_equal "test", result[:name]
  end

  test "truncates backtrace to max frames" do
    backtrace = (1..300).map { |i| "/app/foo.rb:#{i}" }
    result = RailsInformant::ContextFilter.filter_backtrace(backtrace)
    assert_equal 200, result.size
  end

  test "truncates message to max length" do
    long_message = "x" * 3000
    result = RailsInformant::ContextFilter.filter_message(long_message)
    assert_equal 2000, result.length
  end

  test "returns nil for nil input" do
    assert_nil RailsInformant::ContextFilter.filter(nil)
    assert_nil RailsInformant::ContextFilter.filter_backtrace(nil)
    assert_nil RailsInformant::ContextFilter.filter_message(nil)
  end

  test "truncates oversized context" do
    huge = { data: "x" * 100_000 }
    result = RailsInformant::ContextFilter.filter(huge)
    assert result[:_truncated]
    assert result[:_original_size] > 64.kilobytes
  end
end
