require_relative "../test_helper"

module RailsInformant
  module Mcp
    module Tools
      class VerifyPendingFixesTest < Minitest::Test
        include ToolTestHelper

        def setup
          super
          @deploy_sha = "deploy123abc"
          @client.stubs(:status).returns({ "deploy_sha" => @deploy_sha })
          VerifyPendingFixes.stubs(:git_available?).returns(true)
        end

        def test_verifies_and_resolves_pending_fixes
          errors = paginated([
            { "id" => 1, "error_class" => "NoMethodError", "message" => "undefined method 'foo'", "fix_sha" => "abc123", "fix_pr_url" => nil },
            { "id" => 2, "error_class" => "TypeError", "message" => "no implicit conversion", "fix_sha" => "def456", "fix_pr_url" => nil }
          ])
          @client.stubs(:list_errors).with(status: "fix_pending", page: 1, per_page: 100).returns(errors)

          VerifyPendingFixes.stubs(:ancestor?).with("abc123", @deploy_sha).returns(true)
          VerifyPendingFixes.stubs(:ancestor?).with("def456", @deploy_sha).returns(false)

          @client.expects(:update_error).with(1, status: "resolved").once
          @client.expects(:update_error).with(2, status: "resolved").never

          response = VerifyPendingFixes.call(server_context: @server_context)

          refute response.error?
          data = JSON.parse(response.content.first[:text])
          assert_equal 1, data["verified"].size
          assert_equal 1, data["pending"].size
          assert_equal @deploy_sha, data["deploy_sha"]
          assert_equal 1, data["resolved_count"]
        end

        def test_does_not_resolve_when_auto_resolve_false
          errors = paginated([
            { "id" => 1, "error_class" => "NoMethodError", "message" => "err", "fix_sha" => "abc123", "fix_pr_url" => nil }
          ])
          @client.stubs(:list_errors).returns(errors)
          VerifyPendingFixes.stubs(:ancestor?).returns(true)

          @client.expects(:update_error).never

          response = VerifyPendingFixes.call(server_context: @server_context, auto_resolve: false)

          refute response.error?
          data = JSON.parse(response.content.first[:text])
          assert_equal 0, data["resolved_count"]
        end

        def test_requires_git
          VerifyPendingFixes.stubs(:git_available?).returns(false)

          response = VerifyPendingFixes.call(server_context: @server_context)

          assert response.error?
          assert_includes response.content.first[:text], "git is not available"
        end

        def test_returns_error_when_no_deploy_sha
          @client.stubs(:status).returns({ "deploy_sha" => nil })

          response = VerifyPendingFixes.call(server_context: @server_context)

          assert response.error?
          assert_includes response.content.first[:text], "No deploy SHA available"
        end

        def test_rejects_target_ref_starting_with_dash
          response = VerifyPendingFixes.call(server_context: @server_context, target_ref: "--help")

          assert response.error?
          assert_includes response.content.first[:text], "Invalid target_ref"
        end

        def test_reports_empty_when_no_fix_pending_errors
          @client.stubs(:list_errors).returns(paginated([]))

          response = VerifyPendingFixes.call(server_context: @server_context)

          refute response.error?
          data = JSON.parse(response.content.first[:text])
          assert_equal "No fix_pending errors found", data["message"]
        end

        def test_uses_custom_target_ref
          errors = paginated([
            { "id" => 1, "error_class" => "NoMethodError", "message" => "err", "fix_sha" => "abc123", "fix_pr_url" => nil }
          ])
          @client.stubs(:list_errors).returns(errors)
          VerifyPendingFixes.expects(:ancestor?).with("abc123", "main").returns(true)
          @client.stubs(:update_error)

          response = VerifyPendingFixes.call(server_context: @server_context, target_ref: "main")

          refute response.error?
        end

        def test_includes_nil_fix_sha_in_pending
          errors = paginated([
            { "id" => 1, "error_class" => "NoMethodError", "message" => "err", "fix_sha" => nil, "fix_pr_url" => nil },
            { "id" => 2, "error_class" => "TypeError", "message" => "err", "fix_sha" => "abc123", "fix_pr_url" => nil }
          ])
          @client.stubs(:list_errors).returns(errors)
          VerifyPendingFixes.stubs(:ancestor?).with("abc123", @deploy_sha).returns(true)
          @client.stubs(:update_error)

          response = VerifyPendingFixes.call(server_context: @server_context)

          data = JSON.parse(response.content.first[:text])
          assert_equal 1, data["pending"].size
          assert_equal 1, data["verified"].size
        end

        def test_processes_errors_across_multiple_pages
          page1 = { "data" => [ { "id" => 1, "error_class" => "A", "message" => "err", "fix_sha" => "aaa", "fix_pr_url" => nil } ], "meta" => { "page" => 1, "per_page" => 100, "has_more" => true } }
          page2 = { "data" => [ { "id" => 2, "error_class" => "B", "message" => "err", "fix_sha" => "bbb", "fix_pr_url" => nil } ], "meta" => { "page" => 2, "per_page" => 100, "has_more" => false } }

          @client.stubs(:list_errors).with(status: "fix_pending", page: 1, per_page: 100).returns(page1)
          @client.stubs(:list_errors).with(status: "fix_pending", page: 2, per_page: 100).returns(page2)

          VerifyPendingFixes.stubs(:ancestor?).returns(true)
          @client.stubs(:update_error)

          response = VerifyPendingFixes.call(server_context: @server_context)

          data = JSON.parse(response.content.first[:text])
          assert_equal 2, data["verified"].size
        end

        def test_returns_error_on_api_failure
          @client.stubs(:list_errors).raises(Client::Error.new("Connection failed"))

          response = VerifyPendingFixes.call(server_context: @server_context)

          assert response.error?
          assert_includes response.content.first[:text], "Connection failed"
        end
      end
    end
  end
end
