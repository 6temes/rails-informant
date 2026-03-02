module RailsInformant
  module Mcp
    module Tools
      class AnnotateError < BaseTool
        tool_name "annotate_error"
        description "Set investigation notes on an error group (replaces existing notes). Use get_error first to check for existing notes you may want to preserve or append to."
        input_schema(
          properties: {
            environment: { type: "string", description: "Target environment (defaults to first configured)" },
            id: { type: "integer", description: "Error group ID" },
            notes: { type: "string", description: "Investigation notes or analysis (check existing notes with get_error first). Pass empty string to clear." }
          },
          required: %w[id notes]
        )
        annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)

        def self.call(id:, notes:, server_context:, environment: nil)
          with_client(server_context:, environment:) do |client|
            text_response(client.update_error(id, { notes: notes.to_s }))
          end
        end
      end
    end
  end
end
