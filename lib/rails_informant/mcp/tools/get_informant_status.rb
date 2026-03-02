module RailsInformant
  module Mcp
    module Tools
      class GetInformantStatus < BaseTool
        tool_name "get_informant_status"
        description "Get error monitoring summary: unresolved count, deploy SHA, and top errors"
        input_schema(
          properties: {
            environment: { type: "string", description: "Target environment (defaults to first configured)" }
          }
        )
        annotations(read_only_hint: true, destructive_hint: false)

        def self.call(server_context:, environment: nil)
          client = client_for(server_context:, environment:)
          result = client.status
          text_response(result)
        rescue Client::Error => e
          error_response(e.message)
        end
      end
    end
  end
end
