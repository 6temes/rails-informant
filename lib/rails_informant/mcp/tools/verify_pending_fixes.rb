require "json"
require "open3"

module RailsInformant
  module Mcp
    module Tools
      class VerifyPendingFixes < BaseTool
        tool_name "verify_pending_fixes"
        description "Verify fix_pending errors by checking whether the fix is in the deployed code: first by fix_sha ancestry, then — for squash/rebase merges, where fix_sha is not an ancestor of the deploy — by the fix PR's merge commit. Resolves verified fixes. Requires git locally (and gh for the PR fallback). Results reflect local git state — run git fetch first to ensure accuracy."
        input_schema(
          properties: {
            auto_resolve: { type: "boolean", description: "Resolve verified fixes automatically (default: true)" },
            environment: { type: "string", description: "Target environment (defaults to first configured)" },
            target_ref: { type: "string", description: "Git ref to verify against (default: deploy_sha from status API)" }
          }
        )
        annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)

        MAX_PAGES = 10

        class << self
          def call(server_context:, auto_resolve: true, environment: nil, target_ref: nil)
            with_client(server_context:, environment:) do |client|
              return error_response "git is not available. Run this tool from a machine with git installed." unless git_available?

              ref = target_ref || fetch_deploy_sha(client)
              return error_response "No deploy SHA available. Pass target_ref explicitly." unless ref
              return error_response "Invalid target_ref" if ref.start_with?("-")

              errors = fetch_all_fix_pending client
              return text_response("message" => "No fix_pending errors found", "verified" => [], "pending" => []) if errors.empty?

              verified = []
              pending = []

              errors.each do |error|
                if verified?(error, ref)
                  verified << error
                else
                  pending << error
                end
              end

              if auto_resolve && verified.any?
                verified.each { |error| client.update_error error["id"], status: "resolved" }
              end

              text_response(
                "message" => "Verified #{verified.size} of #{errors.size} fix_pending error(s)",
                "deploy_sha" => ref,
                "resolved_count" => auto_resolve ? verified.size : 0,
                "verified" => verified.map { summarize it },
                "pending" => pending.map { summarize it }
              )
            end
          end

          private

          def verified?(error, target_ref)
            fix_sha = error["fix_sha"]
            return true if fix_sha && ancestor?(fix_sha, target_ref)

            # Squash and rebase merges create a new commit unrelated to fix_sha, so the
            # recorded SHA is never an ancestor of the deploy. Fall back to the PR's merge
            # commit, which is in the deployed history regardless of merge strategy.
            merge_sha = merged_pr_commit error["fix_pr_url"]
            !merge_sha.nil? && ancestor?(merge_sha, target_ref)
          end

          def ancestor?(fix_sha, target_ref)
            system "git", "merge-base", "--is-ancestor", fix_sha, target_ref, out: File::NULL, err: File::NULL
          end

          # Returns the merge commit SHA of a merged PR, or nil if the PR is unmerged, the
          # URL is blank, or gh is unavailable. Best-effort fetches the commit so the
          # subsequent ancestry check can see it. Uses the array form (no shell) so the
          # PR URL can't be interpreted as a command.
          def merged_pr_commit(pr_url)
            return if pr_url.nil? || pr_url.empty?
            return unless gh_available?

            output, status = Open3.capture2 "gh", "pr", "view", pr_url, "--json", "state,mergeCommit", err: File::NULL
            return unless status.success? && !output.strip.empty?

            data = JSON.parse output
            return unless data["state"] == "MERGED"

            merge_sha = data.dig "mergeCommit", "oid"
            return if merge_sha.nil? || merge_sha.empty?

            fetch_commit merge_sha
            merge_sha
          rescue JSON::ParserError
            nil
          end

          def fetch_commit(sha)
            system "git", "fetch", "--quiet", "origin", sha, out: File::NULL, err: File::NULL
          end

          def gh_available?
            system "gh", "--version", out: File::NULL, err: File::NULL
          end

          def fetch_all_fix_pending(client)
            errors = []
            page = 1
            loop do
              result = client.list_errors status: "fix_pending", page:, per_page: 100
              errors.concat result["data"]
              break unless result.dig("meta", "has_more")
              page += 1
              break if page > MAX_PAGES
            end
            errors
          end

          def fetch_deploy_sha(client)
            client.status&.dig("deploy_sha")
          end

          def git_available?
            system "git", "rev-parse", "--git-dir", out: File::NULL, err: File::NULL
          end

          def summarize(error)
            { "id" => error["id"], "error_class" => error["error_class"], "message" => error["message"], "fix_sha" => error["fix_sha"], "fix_pr_url" => error["fix_pr_url"] }
          end
        end
      end
    end
  end
end
