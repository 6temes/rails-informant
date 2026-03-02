module RailsInformant
  module Mcp
    module Tools
      class DeleteError < BaseTool
        tool_name "delete_error"
        description "Delete an error group and all its occurrences. This action is irreversible."
        input_schema(
          properties: {
            environment: { type: "string", description: "Target environment (defaults to first configured)" },
            id: { type: "integer", description: "Error group ID" }
          },
          required: [ "id" ]
        )
        annotations(destructive_hint: true)

        def self.call(id:, server_context:, environment: nil)
          client = client_for(server_context:, environment:)
          client.delete_error(id)
          text_response("Error group #{id} deleted successfully")
        rescue Client::Error => e
          error_response(e.message)
        end
      end
    end
  end
end
