module RailsInformant
  module Mcp
    module Tools
      class ResolveError < BaseTool
        tool_name "resolve_error"
        description "Mark an error group as resolved"
        input_schema(
          properties: {
            environment: { type: "string", description: "Target environment (defaults to first configured)" },
            id: { type: "integer", description: "Error group ID" }
          },
          required: [ "id" ]
        )
        annotations(destructive_hint: false)

        def self.call(id:, server_context:, environment: nil)
          client = client_for(server_context:, environment:)
          result = client.update_error(id, { status: "resolved" })
          text_response(result)
        rescue Client::Error => e
          error_response(e.message)
        end
      end
    end
  end
end
