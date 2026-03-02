require_relative "../test_helper"

module RailsInformant
  module Mcp
    module Tools
      class MarkFixPendingTest < Minitest::Test
        include ToolTestHelper

        def test_marks_fix_pending
          result = { "id" => 1, "status" => "fix_pending", "fix_sha" => "abc123", "original_sha" => "def456" }
          @client.expects(:fix_pending).with(1, fix_sha: "abc123", original_sha: "def456", fix_pr_url: nil).returns(result)

          response = MarkFixPending.call(
            id: 1, fix_sha: "abc123", original_sha: "def456", server_context: @server_context
          )

          refute response.error?
          data = JSON.parse(response.content.first[:text])
          assert_equal "fix_pending", data["status"]
          assert_equal "abc123", data["fix_sha"]
        end

        def test_marks_fix_pending_with_pr_url
          result = { "id" => 1, "status" => "fix_pending", "fix_pr_url" => "https://github.com/org/repo/pull/42" }
          @client.expects(:fix_pending).with(1, fix_sha: "abc123", original_sha: "def456", fix_pr_url: "https://github.com/org/repo/pull/42").returns(result)

          response = MarkFixPending.call(
            id: 1, fix_sha: "abc123", original_sha: "def456",
            fix_pr_url: "https://github.com/org/repo/pull/42", server_context: @server_context
          )

          refute response.error?
        end

        def test_returns_error_on_invalid_transition
          @client.stubs(:fix_pending).raises(Client::Error.new("Invalid transition from fix_pending to fix_pending"))

          response = MarkFixPending.call(
            id: 1, fix_sha: "abc123", original_sha: "def456", server_context: @server_context
          )

          assert response.error?
          assert_includes response.content.first[:text], "Invalid transition"
        end
      end
    end
  end
end
