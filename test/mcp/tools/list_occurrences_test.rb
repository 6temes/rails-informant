require_relative "../test_helper"

module RailsInformant
  module Mcp
    module Tools
      class ListOccurrencesTest < Minitest::Test
        include ToolTestHelper

        def test_returns_occurrences
          occurrences = [
            { "id" => 10, "error_group_id" => 1, "backtrace" => [ "/app/models/user.rb:42" ] }
          ]
          @client.stubs(:list_occurrences).returns(paginated(occurrences))

          response = ListOccurrences.call(server_context: @server_context)

          refute response.error?
          data = JSON.parse(response.content.first[:text].split("\n\n").first)
          assert_equal 1, data.size
          assert_equal 10, data.first["id"]
        end

        def test_passes_filters_to_client
          @client.expects(:list_occurrences).with(error_group_id: 1, since: "2026-03-01T00:00:00Z").returns(paginated([]))

          ListOccurrences.call(server_context: @server_context, error_group_id: 1, since: "2026-03-01T00:00:00Z")
        end

        def test_returns_error_on_client_failure
          @client.stubs(:list_occurrences).raises(Client::Error.new("Connection failed"))

          response = ListOccurrences.call(server_context: @server_context)

          assert response.error?
          assert_equal "Connection failed", response.content.first[:text]
        end
      end
    end
  end
end
