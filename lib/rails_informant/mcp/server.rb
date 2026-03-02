module RailsInformant
  module Mcp
    class Server
      TOOLS = [
        Tools::AnnotateError,
        Tools::DeleteError,
        Tools::GetError,
        Tools::GetInformantStatus,
        Tools::IgnoreError,
        Tools::ListEnvironments,
        Tools::ListErrors,
        Tools::ListOccurrences,
        Tools::MarkDuplicate,
        Tools::MarkFixPending,
        Tools::ReopenError,
        Tools::ResolveError
      ].freeze

      def self.build(config)
        ::MCP::Server.new(
          name: "informant",
          version: VERSION,
          tools: TOOLS,
          server_context: { config: }
        )
      end
    end
  end
end
