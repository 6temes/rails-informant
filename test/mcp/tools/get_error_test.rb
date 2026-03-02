require_relative "../test_helper"

module RailsInformant
  module Mcp
    module Tools
      class GetErrorTest < Minitest::Test
        def setup
          @client = Client.new(url: "https://test.example.com", token: "test-token")
          @config = mock("config")
          @config.stubs(:default_environment).returns("production")
          @config.stubs(:client_for).with("production").returns(@client)
          @server_context = { config: @config }
        end

        def test_returns_error_detail
          error_data = {
            "id" => 1,
            "error_class" => "NoMethodError",
            "message" => "undefined method 'foo'",
            "recent_occurrences" => [
              { "id" => 10, "backtrace" => [ "/app/models/user.rb:42" ] }
            ]
          }
          @client.stubs(:get_error).with(1).returns(error_data)

          response = GetError.call(id: 1, server_context: @server_context)

          refute response.error?
          data = JSON.parse(response.content.first[:text])
          assert_equal "NoMethodError", data["error_class"]
          assert_equal 1, data["recent_occurrences"].size
        end

        def test_returns_error_on_not_found
          @client.stubs(:get_error).with(999).raises(Client::Error.new("Not found (404)"))

          response = GetError.call(id: 999, server_context: @server_context)

          assert response.error?
          assert_includes response.content.first[:text], "Not found"
        end
      end
    end
  end
end
