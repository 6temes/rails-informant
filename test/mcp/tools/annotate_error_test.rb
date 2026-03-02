require_relative "../test_helper"

module RailsInformant
  module Mcp
    module Tools
      class AnnotateErrorTest < Minitest::Test
        include ToolTestHelper

        def test_annotates_error_with_notes
          result = { "id" => 1, "notes" => "Caused by Redis timeout during peak traffic" }
          @client.expects(:update_error).with(1, { notes: "Caused by Redis timeout during peak traffic" }).returns(result)

          response = AnnotateError.call(id: 1, notes: "Caused by Redis timeout during peak traffic", server_context: @server_context)

          refute response.error?
          data = JSON.parse(response.content.first[:text])
          assert_equal 1, data["id"]
          assert_equal "Caused by Redis timeout during peak traffic", data["notes"]
        end

        def test_clears_notes_with_empty_string
          result = { "id" => 1, "notes" => "" }
          @client.expects(:update_error).with(1, { notes: "" }).returns(result)

          response = AnnotateError.call(id: 1, notes: "", server_context: @server_context)

          refute response.error?
          data = JSON.parse(response.content.first[:text])
          assert_equal 1, data["id"]
          assert_equal "", data["notes"]
        end

        def test_returns_error_on_not_found
          @client.stubs(:update_error).raises(Client::Error.new("Not found (404)"))

          response = AnnotateError.call(id: 999, notes: "test", server_context: @server_context)

          assert response.error?
          assert_includes response.content.first[:text], "Not found"
        end
      end
    end
  end
end
