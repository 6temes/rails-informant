require_relative "../test_helper"

module RailsInformant
  module Mcp
    module Tools
      class GetInformantStatusTest < Minitest::Test
        def setup
          @client = Client.new(url: "https://test.example.com", token: "test-token")
          @config = mock("config")
          @config.stubs(:default_environment).returns("production")
          @config.stubs(:client_for).with("production").returns(@client)
          @server_context = { config: @config }
        end

        def test_returns_status_summary
          status_data = {
            "unresolved_count" => 5,
            "fix_pending_count" => 2,
            "resolved_count" => 10,
            "ignored_count" => 1,
            "deploy_sha" => "abc123",
            "top_errors" => [
              { "id" => 1, "error_class" => "NoMethodError", "total_occurrences" => 42 }
            ]
          }
          @client.stubs(:status).returns(status_data)

          response = GetInformantStatus.call(server_context: @server_context)

          refute response.error?
          data = JSON.parse(response.content.first[:text])
          assert_equal 5, data["unresolved_count"]
          assert_equal "abc123", data["deploy_sha"]
          assert_equal 1, data["top_errors"].size
        end

        def test_returns_error_on_auth_failure
          @client.stubs(:status).raises(Client::Error.new("Authentication failed. Check your API token."))

          response = GetInformantStatus.call(server_context: @server_context)

          assert response.error?
          assert_includes response.content.first[:text], "Authentication failed"
        end
      end
    end
  end
end
