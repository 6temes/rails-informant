require "test_helper"

class RailsInformant::BrowserContextTest < ActiveSupport::TestCase
  USER = { "class" => "User", "email" => "jane@example.com", "id" => 7 }.freeze

  setup do
    RailsInformant.stubs(:current_git_sha).returns("abc1234")
    @default_serializer = ActiveSupport::Messages::Codec.default_serializer
  end

  teardown do
    ActiveSupport::Messages::Codec.default_serializer = @default_serializer
  end

  test "a blob round-trips the user, request ID, revision and render time under either host serializer" do
    freeze_time

    %i[json marshal].each do |serializer|
      ActiveSupport::Messages::Codec.default_serializer = serializer

      context = RailsInformant::BrowserContext.verify(generate)

      assert_equal USER, context.user_context, serializer
      assert_equal "req-render", context.request_id
      assert_equal "abc1234", context.revision
      assert_equal Time.current, context.rendered_at
    end
  end

  test "a tampered blob or one that is not a string verifies to nil" do
    blob = generate
    tampered = blob.sub(/\A./) { it == "A" ? "B" : "A" }

    assert_nil RailsInformant::BrowserContext.verify(tampered)
    assert_nil RailsInformant::BrowserContext.verify(nil)
    assert_nil RailsInformant::BrowserContext.verify({ "user_context" => USER })
  end

  test "a blob rendered over 24 hours ago keeps its render time and revision but drops identity" do
    blob = travel_to(25.hours.ago) { generate }

    context = RailsInformant::BrowserContext.verify(blob)

    assert_in_delta 25.hours.ago, context.rendered_at, 1
    assert_equal "abc1234", context.revision
    assert_nil context.user_context
    assert_nil context.request_id
  end

  test "the blob does not expose the user in readable form" do
    decoded = generate.split("--").map { Base64.strict_decode64(it) }.join

    assert_not_includes decoded, "jane@example.com"
    assert_not_includes decoded, "\"id\":7"
  end

  private

  def generate
    RailsInformant::Current.user_context = { class: "User", email: "jane@example.com", id: 7 }
    RailsInformant::BrowserContext.generate ActionDispatch::TestRequest.create("action_dispatch.request_id" => "req-render")
  ensure
    RailsInformant::Current.user_context = nil
  end
end
