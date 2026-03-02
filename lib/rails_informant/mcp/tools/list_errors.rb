module RailsInformant
  module Mcp
    module Tools
      class ListErrors < BaseTool
        tool_name "list_errors"
        description "List error groups with filtering. Excludes duplicates by default unless status=duplicate is specified. Returns paginated results ordered by last seen."
        input_schema(
          properties: {
            environment: { type: "string", description: "Target environment (defaults to first configured)" },
            status: { type: "string", enum: %w[duplicate fix_pending ignored resolved unresolved], description: "Filter by status (duplicate errors are excluded by default; pass status=duplicate to list them)" },
            error_class: { type: "string", description: "Filter by exception class name" },
            controller_action: { type: "string", description: "Filter by controller#action" },
            job_class: { type: "string", description: "Filter by background job class" },
            q: { type: "string", description: "Search error messages" },
            severity: { type: "string", enum: %w[error info warning], description: "Filter by severity" },
            since: { type: "string", description: "ISO 8601 datetime — only errors last seen after this time" },
            until: { type: "string", description: "ISO 8601 datetime — only errors last seen before this time" },
            page: { type: "integer", description: "Page number (default 1)" },
            per_page: { type: "integer", description: "Results per page (default 20, max 100)" }
          }
        )
        annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)

        def self.call(server_context:, environment: nil, **params)
          with_client(server_context:, environment:) do |client|
            paginated_text_response(client.list_errors(**params.compact))
          end
        end
      end
    end
  end
end
