require "test_helper"

class RailsInformant::Notifiers::CircuitBreakerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "closed by default" do
    assert_not RailsInformant::Notifiers::CircuitBreaker.open?
  end

  test "stays closed below failure threshold" do
    4.times { RailsInformant::Notifiers::CircuitBreaker.record_failure }

    assert_not RailsInformant::Notifiers::CircuitBreaker.open?
  end

  test "opens after reaching failure threshold" do
    5.times { RailsInformant::Notifiers::CircuitBreaker.record_failure }

    assert RailsInformant::Notifiers::CircuitBreaker.open?
  end

  test "resets on success" do
    5.times { RailsInformant::Notifiers::CircuitBreaker.record_failure }
    assert RailsInformant::Notifiers::CircuitBreaker.open?

    RailsInformant::Notifiers::CircuitBreaker.record_success

    assert_not RailsInformant::Notifiers::CircuitBreaker.open?
  end

  test "auto-resets after timeout" do
    5.times { RailsInformant::Notifiers::CircuitBreaker.record_failure }
    assert RailsInformant::Notifiers::CircuitBreaker.open?

    travel 11.minutes

    assert_not RailsInformant::Notifiers::CircuitBreaker.open?
  end

  test "skips NotifyJob enqueue when circuit is open" do
    RailsInformant.config.slack_webhook_url = "https://hooks.slack.com/test"
    5.times { RailsInformant::Notifiers::CircuitBreaker.record_failure }

    assert_no_enqueued_jobs only: RailsInformant::NotifyJob do
      RailsInformant::ErrorRecorder.record build_error
    end
  end

  private

  def build_error(message = "boom")
    error = StandardError.new(message)
    error.set_backtrace [ "/app/models/user.rb:42:in `save'" ]
    error
  end
end
