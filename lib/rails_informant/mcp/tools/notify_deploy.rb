module RailsInformant
  module Mcp
    module Tools
      class NotifyDeploy < BaseTool
        tool_name "notify_deploy"
        description "Notify Informant of a deploy. Auto-resolves unresolved errors not seen in the last hour. Returns count of resolved errors."
        input_schema(
          properties: {
            environment: { type: "string", description: "Target environment (defaults to first configured)" },
            sha: { type: "string", description: "Git SHA of the deployed commit" }
          },
          required: %w[sha]
        )
        annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: true)

        def self.call(sha:, server_context:, environment: nil)
          with_client(server_context:, environment:) do |client|
            text_response(client.notify_deploy(sha:))
          end
        end
      end
    end
  end
end
