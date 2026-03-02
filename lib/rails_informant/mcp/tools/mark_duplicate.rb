module RailsInformant
  module Mcp
    module Tools
      class MarkDuplicate < BaseTool
        tool_name "mark_duplicate"
        description "Mark an error group as a duplicate of another error group"
        input_schema(
          properties: {
            environment: { type: "string", description: "Target environment (defaults to first configured)" },
            id: { type: "integer", description: "Error group ID to mark as duplicate" },
            duplicate_of_id: { type: "integer", description: "ID of the canonical error group" }
          },
          required: %w[id duplicate_of_id]
        )
        annotations(destructive_hint: false)

        def self.call(id:, duplicate_of_id:, server_context:, environment: nil)
          client = client_for(server_context:, environment:)
          result = client.mark_duplicate(id, duplicate_of_id:)
          text_response(result)
        rescue Client::Error => e
          error_response(e.message)
        end
      end
    end
  end
end
