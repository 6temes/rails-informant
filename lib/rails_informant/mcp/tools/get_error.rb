module RailsInformant
  module Mcp
    module Tools
      class GetError < BaseTool
        tool_name "get_error"
        description "Get full error details including notes, fix_sha, fix_pr_url, and up to 10 recent occurrences with backtraces, request context, and breadcrumbs"
        input_schema(
          properties: {
            environment: { type: "string", description: "Target environment (defaults to first configured)" },
            id: { type: "integer", description: "Error group ID" }
          },
          required: %w[id]
        )
        annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

        def self.call(id:, server_context:, environment: nil)
          with_client(server_context:, environment:) do |client|
            text_response(client.get_error(id))
          end
        end
      end
    end
  end
end
