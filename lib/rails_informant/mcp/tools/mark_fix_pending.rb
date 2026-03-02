module RailsInformant
  module Mcp
    module Tools
      class MarkFixPending < BaseTool
        tool_name "mark_fix_pending"
        description "Mark as fix_pending (unresolved → fix_pending) with the fix commit SHA, original SHA, and optional PR URL. The server auto-resolves when the fix is deployed. Valid from: unresolved."
        input_schema(
          properties: {
            environment: { type: "string", description: "Target environment (defaults to first configured)" },
            id: { type: "integer", description: "Error group ID" },
            fix_sha: { type: "string", description: "Git SHA of the fix commit" },
            original_sha: { type: "string", description: "Git SHA of the deploy where the error occurred" },
            fix_pr_url: { type: "string", description: "URL of the pull request with the fix" }
          },
          required: %w[id fix_sha original_sha]
        )
        annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)

        def self.call(id:, fix_sha:, original_sha:, server_context:, environment: nil, fix_pr_url: nil)
          with_client(server_context:, environment:) do |client|
            text_response(client.fix_pending(id, fix_sha:, original_sha:, fix_pr_url:))
          end
        end
      end
    end
  end
end
