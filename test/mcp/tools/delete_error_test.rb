require_relative "../test_helper"

module RailsInformant
  module Mcp
    module Tools
      class DeleteErrorTest < Minitest::Test
        include ToolTestHelper

        def test_deletes_error
          @client.expects(:delete_error).with(1).returns(nil)

          response = DeleteError.call(id: 1, server_context: @server_context)

          refute response.error?
          assert_includes response.content.first[:text], "Error group 1 deleted successfully"
        end

        def test_returns_error_on_not_found
          @client.stubs(:delete_error).raises(Client::Error.new("Not found (404)"))

          response = DeleteError.call(id: 999, server_context: @server_context)

          assert response.error?
          assert_includes response.content.first[:text], "Not found"
        end
      end
    end
  end
end
