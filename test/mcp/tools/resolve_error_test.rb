require_relative "../test_helper"

module RailsInformant
  module Mcp
    module Tools
      class ResolveErrorTest < Minitest::Test
        def setup
          @client = Client.new(url: "https://test.example.com", token: "test-token")
          @config = mock("config")
          @config.stubs(:default_environment).returns("production")
          @config.stubs(:client_for).with("production").returns(@client)
          @server_context = { config: @config }
        end

        def test_resolves_error
          resolved = { "id" => 1, "status" => "resolved", "resolved_at" => "2026-03-01T12:00:00Z" }
          @client.expects(:update_error).with(1, { status: "resolved" }).returns(resolved)

          response = ResolveError.call(id: 1, server_context: @server_context)

          refute response.error?
          data = JSON.parse(response.content.first[:text])
          assert_equal "resolved", data["status"]
        end

        def test_returns_error_on_invalid_transition
          @client.stubs(:update_error).raises(Client::Error.new("Invalid transition from resolved to resolved"))

          response = ResolveError.call(id: 1, server_context: @server_context)

          assert response.error?
          assert_includes response.content.first[:text], "Invalid transition"
        end
      end
    end
  end
end
