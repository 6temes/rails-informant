module RailsInformant
  module Mcp
    module Tools
      class AnnotateError < BaseTool
        tool_name "annotate_error"
        description "Add or update investigation notes on an error group"
        input_schema(
          properties: {
            environment: { type: "string", description: "Target environment (defaults to first configured)" },
            id: { type: "integer", description: "Error group ID" },
            notes: { type: "string", description: "Investigation notes or analysis" }
          },
          required: %w[id notes]
        )
        annotations(destructive_hint: false)

        def self.call(id:, notes:, server_context:, environment: nil)
          client = client_for(server_context:, environment:)
          result = client.update_error(id, { notes: })
          text_response(result)
        rescue Client::Error => e
          error_response(e.message)
        end
      end
    end
  end
end
