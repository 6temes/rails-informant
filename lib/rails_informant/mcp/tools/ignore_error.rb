module RailsInformant
  module Mcp
    module Tools
      class IgnoreError < BaseTool
        tool_name "ignore_error"
        description "Mark as ignored (unresolved → ignored). Valid from: unresolved."
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
            text_response(client.update_error(id, { status: "ignored" }))
          end
        end
      end
    end
  end
end
