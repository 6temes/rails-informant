require "test_helper"

class RailsInformant::Notifiers::WebhookTest < ActiveSupport::TestCase
  setup do
    @notifier = RailsInformant::Notifiers::Webhook.new
    RailsInformant.config.webhook_url = "https://example.com/webhook"
  end

  test "notify sends HTTP POST with JSON payload" do
    group = create_group
    occurrence = group.occurrences.create!(
      backtrace: [ "/app/foo.rb:1" ],
      git_sha: "abc123"
    )

    payload = nil
    Net::HTTP.stubs(:post).with { |_, body, _| payload = JSON.parse(body); true }

    @notifier.notify(group, occurrence)

    assert_equal "StandardError", payload["error_class"]
    assert_equal group.fingerprint, payload["fingerprint"]
    assert_nil payload["occurrence"]
  end

  test "includes occurrence context when webhook_include_context is true" do
    RailsInformant.config.webhook_include_context = true

    group = create_group
    occurrence = group.occurrences.create!(
      backtrace: [ "/app/foo.rb:1" ],
      environment_context: { "rails_env" => "production" },
      git_sha: "abc123"
    )

    payload = nil
    Net::HTTP.stubs(:post).with { |_, body, _| payload = JSON.parse(body); true }

    @notifier.notify(group, occurrence)

    assert payload["occurrence"].present?
    assert_equal "abc123", payload["occurrence"]["git_sha"]
  end

  test "strips PII by default" do
    group = create_group
    occurrence = group.occurrences.create!(
      backtrace: [ "/app/foo.rb:1" ],
      user_context: { "id" => 42, "email" => "test@example.com" }
    )

    payload = nil
    Net::HTTP.stubs(:post).with { |_, body, _| payload = JSON.parse(body); true }

    @notifier.notify(group, occurrence)

    assert_nil payload["user_context"]
    assert_nil payload["occurrence"]
  end

  private

  def create_group
    RailsInformant::ErrorGroup.create!(
      fingerprint: SecureRandom.hex(8),
      error_class: "StandardError",
      message: "test error",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )
  end
end
