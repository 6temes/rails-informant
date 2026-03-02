module RailsInformant
  module Mcp
    module Tools
      class ListEnvironments < BaseTool
        tool_name "list_environments"
        description "List configured environments and their URLs"
        input_schema(properties: {})
        annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

        def self.call(server_context:)
          config = server_context[:config]
          envs = config.safe_environments.map do |name, env|
            { name:, url: env[:url], default: name == config.default_environment }
          end
          text_response(envs)
        end
      end
    end
  end
end
