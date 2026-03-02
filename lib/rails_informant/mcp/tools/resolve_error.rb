module RailsInformant
  module Mcp
    module Tools
      class ResolveError < BaseTool
        tool_name "resolve_error"
        description "Mark as resolved (unresolved/fix_pending → resolved). Valid from: unresolved, fix_pending."
        input_schema(
          properties: {
            environment: { type: "string", description: "Target environment (defaults to first configured)" },
            id: { type: "integer", description: "Error group ID" }
          },
          required: %w[id]
        )
        annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)

        def self.call(id:, server_context:, environment: nil)
          with_client(server_context:, environment:) do |client|
            text_response(client.update_error(id, { status: "resolved" }))
          end
        end
      end
    end
  end
end
