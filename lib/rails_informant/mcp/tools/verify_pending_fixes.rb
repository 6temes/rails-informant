module RailsInformant
  module Mcp
    module Tools
      class VerifyPendingFixes < BaseTool
        tool_name "verify_pending_fixes"
        description "Verify fix_pending errors by checking if their fix_sha is an ancestor of the deployed code. Resolves verified fixes. Requires git locally. Results reflect local git state — run git fetch first to ensure accuracy."
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
                fix_sha = error["fix_sha"]
                if fix_sha && ancestor?(fix_sha, ref)
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

          def ancestor?(fix_sha, target_ref)
            system "git", "merge-base", "--is-ancestor", fix_sha, target_ref, out: File::NULL, err: File::NULL
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
