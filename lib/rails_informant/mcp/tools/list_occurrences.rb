module RailsInformant
  module Mcp
    module Tools
      class ListOccurrences < BaseTool
        tool_name "list_occurrences"
        description "List error occurrences with filtering. Each occurrence includes backtrace, request context, and breadcrumbs."
        input_schema(
          properties: {
            environment: { type: "string", description: "Target environment (defaults to first configured)" },
            error_group_id: { type: "integer", description: "Filter by error group ID" },
            since: { type: "string", description: "ISO 8601 datetime — only occurrences after this time" },
            until: { type: "string", description: "ISO 8601 datetime — only occurrences before this time" },
            page: { type: "integer", description: "Page number" },
            per_page: { type: "integer", description: "Results per page" }
          }
        )
        annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

        def self.call(server_context:, environment: nil, **params)
          with_client(server_context:, environment:) do |client|
            paginated_text_response(client.list_occurrences(**params.compact))
          end
        end
      end
    end
  end
end
