module RailsInformant
  module Mcp
    module Tools
      class ListErrors < BaseTool
        tool_name "list_errors"
        description "List error groups with filtering. Returns paginated results ordered by last seen."
        input_schema(
          properties: {
            environment: { type: "string", description: "Target environment (defaults to first configured)" },
            status: { type: "string", enum: %w[unresolved fix_pending resolved ignored], description: "Filter by status" },
            error_class: { type: "string", description: "Filter by exception class name" },
            q: { type: "string", description: "Search error messages" },
            since: { type: "string", description: "ISO 8601 datetime — only errors last seen after this time" },
            until: { type: "string", description: "ISO 8601 datetime — only errors last seen before this time" },
            page: { type: "integer", description: "Page number (default 1)" },
            per_page: { type: "integer", description: "Results per page (default 20, max 100)" }
          }
        )
        annotations(read_only_hint: true, destructive_hint: false)

        def self.call(server_context:, environment: nil, **params)
          client = client_for(server_context:, environment:)
          result = client.list_errors(**params.compact)
          paginated_text_response(result)
        rescue Client::Error => e
          error_response(e.message)
        end
      end
    end
  end
end
