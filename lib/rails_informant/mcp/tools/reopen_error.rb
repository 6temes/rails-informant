module RailsInformant
  module Mcp
    module Tools
      class ReopenError < BaseTool
        tool_name "reopen_error"
        description "Reopen an error group (resolved/ignored/fix_pending/duplicate → unresolved). Valid from: resolved, ignored, fix_pending, duplicate."
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
            text_response(client.update_error(id, { status: "unresolved" }))
          end
        end
      end
    end
  end
end
