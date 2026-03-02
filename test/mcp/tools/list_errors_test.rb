require_relative "../test_helper"

module RailsInformant
  module Mcp
    module Tools
      class ListErrorsTest < Minitest::Test
        def setup
          @client = Client.new(url: "https://test.example.com", token: "test-token")
          @config = mock("config")
          @config.stubs(:default_environment).returns("production")
          @config.stubs(:client_for).with("production").returns(@client)
          @server_context = { config: @config }
        end

        def test_returns_error_list
          errors = [ { "id" => 1, "error_class" => "StandardError", "message" => "test" } ]
          @client.stubs(:list_errors).returns(errors)

          response = ListErrors.call(server_context: @server_context)

          assert_kind_of ::MCP::Tool::Response, response
          refute response.error?
          data = JSON.parse(response.content.first[:text])
          assert_equal 1, data.size
          assert_equal "StandardError", data.first["error_class"]
        end

        def test_passes_filters_to_client
          @client.expects(:list_errors).with(status: "resolved", q: "timeout").returns([])

          ListErrors.call(server_context: @server_context, status: "resolved", q: "timeout")
        end

        def test_uses_specified_environment
          staging_client = Client.new(url: "https://staging.example.com", token: "staging-token")
          staging_client.stubs(:list_errors).returns([])
          @config.stubs(:client_for).with("staging").returns(staging_client)

          ListErrors.call(server_context: @server_context, environment: "staging")
        end

        def test_returns_error_on_client_failure
          @client.stubs(:list_errors).raises(Client::Error.new("Connection failed"))

          response = ListErrors.call(server_context: @server_context)

          assert response.error?
          assert_equal "Connection failed", response.content.first[:text]
        end
      end
    end
  end
end
