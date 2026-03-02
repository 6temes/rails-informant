require_relative "../test_helper"

module RailsInformant
  module Mcp
    module Tools
      class ReopenErrorTest < Minitest::Test
        include ToolTestHelper

        def test_reopens_error
          result = { "id" => 1, "status" => "unresolved" }
          @client.expects(:update_error).with(1, { status: "unresolved" }).returns(result)

          response = ReopenError.call(id: 1, server_context: @server_context)

          refute response.error?
          data = JSON.parse(response.content.first[:text])
          assert_equal "unresolved", data["status"]
        end

        def test_returns_error_on_invalid_transition
          @client.stubs(:update_error).raises(Client::Error.new("Invalid transition from unresolved to unresolved"))

          response = ReopenError.call(id: 1, server_context: @server_context)

          assert response.error?
          assert_includes response.content.first[:text], "Invalid transition"
        end
      end
    end
  end
end
