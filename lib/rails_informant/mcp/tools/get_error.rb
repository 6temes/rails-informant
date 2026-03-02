module RailsInformant
  module Mcp
    module Tools
      class GetError < BaseTool
        tool_name "get_error"
        description "Get full error group detail including recent occurrences with backtraces, request context, and breadcrumbs"
        input_schema(
          properties: {
            environment: { type: "string", description: "Target environment (defaults to first configured)" },
            id: { type: "integer", description: "Error group ID" }
          },
          required: [ "id" ]
        )
        annotations(read_only_hint: true, destructive_hint: false)

        def self.call(id:, server_context:, environment: nil)
          client = client_for(server_context:, environment:)
          result = client.get_error(id)
          text_response(result)
        rescue Client::Error => e
          error_response(e.message)
        end
      end
    end
  end
end
