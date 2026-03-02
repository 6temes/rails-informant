require_relative "../test_helper"

module RailsInformant
  module Mcp
    module Tools
      class ListEnvironmentsTest < Minitest::Test
        def setup
          @config = mock("config")
          @config.stubs(:default_environment).returns("production")
          @config.stubs(:safe_environments).returns({
            "production" => { url: "https://app.example.com" },
            "staging" => { url: "https://staging.example.com" }
          })
          @server_context = { config: @config }
        end

        def test_lists_configured_environments
          response = ListEnvironments.call(server_context: @server_context)

          refute response.error?
          data = JSON.parse(response.content.first[:text])
          assert_equal 2, data.size
          assert_equal "production", data.first["name"]
          assert_equal true, data.first["default"]
          assert_equal "staging", data.last["name"]
          assert_equal false, data.last["default"]
        end

        def test_does_not_expose_tokens
          response = ListEnvironments.call(server_context: @server_context)

          text = response.content.first[:text]
          refute_includes text, "token"
        end

        def test_single_environment
          @config.stubs(:safe_environments).returns({
            "production" => { url: "https://app.example.com" }
          })

          response = ListEnvironments.call(server_context: @server_context)

          refute response.error?
          data = JSON.parse(response.content.first[:text])
          assert_equal 1, data.size
          assert_equal true, data.first["default"]
        end
      end
    end
  end
end
