module RailsInformant
  module Mcp
    module Tools
      class GetInformantStatus < BaseTool
        tool_name "get_informant_status"
        description "Get error monitoring summary: counts by status (unresolved, resolved, ignored, fix_pending, duplicate), deploy SHA, and top errors"
        input_schema(
          properties: {
            environment: { type: "string", description: "Target environment (defaults to first configured)" }
          }
        )
        annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

        def self.call(server_context:, environment: nil)
          with_client(server_context:, environment:) do |client|
            text_response(client.status)
          end
        end
      end
    end
  end
end
