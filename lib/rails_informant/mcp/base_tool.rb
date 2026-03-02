module RailsInformant
  module Mcp
    class BaseTool < ::MCP::Tool
      class << self
        private

        def client_for(server_context:, environment: nil)
          config = server_context[:config]
          env = environment || config.default_environment
          config.client_for(env)
        end

        def with_client(server_context:, environment: nil)
          client = client_for(server_context:, environment:)
          yield client
        rescue Client::Error => e
          error_response(e.message)
        end

        def text_response(data)
          text = data.is_a?(String) ? data : JSON.generate(data)
          ::MCP::Tool::Response.new([ { type: "text", text: } ])
        end

        def error_response(message)
          ::MCP::Tool::Response.new([ { type: "text", text: message } ], error: true)
        end

        def paginated_text_response(result)
          response_text = JSON.generate(result["data"])
          meta = result["meta"]
          response_text += "\n\nPage #{meta["page"]}, per_page: #{meta["per_page"]}, has_more: #{meta["has_more"]}" if meta
          text_response(response_text)
        end
      end
    end
  end
end
