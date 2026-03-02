require_relative "../test_helper"

module RailsInformant
  module Mcp
    module Tools
      class MarkDuplicateTest < Minitest::Test
        include ToolTestHelper

        def test_marks_duplicate
          result = { "id" => 2, "status" => "duplicate", "duplicate_of_id" => 1 }
          @client.expects(:mark_duplicate).with(2, duplicate_of_id: 1).returns(result)

          response = MarkDuplicate.call(id: 2, duplicate_of_id: 1, server_context: @server_context)

          refute response.error?
          data = JSON.parse(response.content.first[:text])
          assert_equal "duplicate", data["status"]
          assert_equal 1, data["duplicate_of_id"]
        end

        def test_returns_error_on_self_reference
          @client.stubs(:mark_duplicate).raises(Client::Error.new("Cannot mark as duplicate of itself"))

          response = MarkDuplicate.call(id: 1, duplicate_of_id: 1, server_context: @server_context)

          assert response.error?
          assert_includes response.content.first[:text], "duplicate of itself"
        end

        def test_returns_error_on_circular_chain
          @client.stubs(:mark_duplicate).raises(Client::Error.new("Circular duplicate chain detected"))

          response = MarkDuplicate.call(id: 1, duplicate_of_id: 2, server_context: @server_context)

          assert response.error?
          assert_includes response.content.first[:text], "Circular"
        end
      end
    end
  end
end
