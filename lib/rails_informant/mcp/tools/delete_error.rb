module RailsInformant
  module Mcp
    module Tools
      class DeleteError < BaseTool
        tool_name "delete_error"
        description "Permanently delete an error group and all its occurrences. Irreversible. Prefer resolve or ignore over deletion — error history is valuable for regression detection."
        input_schema(
          properties: {
            environment: { type: "string", description: "Target environment (defaults to first configured)" },
            id: { type: "integer", description: "Error group ID" }
          },
          required: %w[id]
        )
        annotations(read_only_hint: false, destructive_hint: true, idempotent_hint: true)

        def self.call(id:, server_context:, environment: nil)
          with_client(server_context:, environment:) do |client|
            client.delete_error(id)
            text_response("Error group #{id} deleted successfully")
          end
        end
      end
    end
  end
end
