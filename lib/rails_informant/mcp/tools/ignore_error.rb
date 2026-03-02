module RailsInformant
  module Mcp
    module Tools
      class IgnoreError < BaseTool
        tool_name "ignore_error"
        description "Mark an error group as ignored"
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
          result = client.update_error(id, { status: "ignored" })
          text_response(result)
        rescue Client::Error => e
          error_response(e.message)
        end
      end
    end
  end
end
