require_relative "../test_helper"

module RailsInformant
  module Mcp
    module Tools
      class NotifyDeployTest < Minitest::Test
        include ToolTestHelper

        def test_notifies_deploy_with_sha
          result = { "resolved_count" => 3, "sha" => "abc1234" }
          @client.expects(:notify_deploy).with(sha: "abc1234").returns(result)

          response = NotifyDeploy.call(sha: "abc1234", server_context: @server_context)

          refute response.error?
          data = JSON.parse(response.content.first[:text])
          assert_equal 3, data["resolved_count"]
          assert_equal "abc1234", data["sha"]
        end

        def test_returns_error_on_invalid_sha
          @client.stubs(:notify_deploy).raises(Client::Error.new("Invalid SHA format"))

          response = NotifyDeploy.call(sha: "bad!", server_context: @server_context)

          assert response.error?
          assert_includes response.content.first[:text], "Invalid SHA format"
        end
      end
    end
  end
end
