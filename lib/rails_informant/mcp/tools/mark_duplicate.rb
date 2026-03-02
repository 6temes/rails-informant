module RailsInformant
  module Mcp
    module Tools
      class MarkDuplicate < BaseTool
        tool_name "mark_duplicate"
        description "Mark as duplicate (unresolved → duplicate) of another error group. Valid from: unresolved."
        input_schema(
          properties: {
            environment: { type: "string", description: "Target environment (defaults to first configured)" },
            id: { type: "integer", description: "Error group ID to mark as duplicate" },
            duplicate_of_id: { type: "integer", description: "ID of the canonical error group" }
          },
          required: %w[id duplicate_of_id]
        )
        annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)

        def self.call(id:, duplicate_of_id:, server_context:, environment: nil)
          with_client(server_context:, environment:) do |client|
            text_response(client.mark_duplicate(id, duplicate_of_id:))
          end
        end
      end
    end
  end
end
