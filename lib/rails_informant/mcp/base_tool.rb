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

        def text_response(data)
          text = data.is_a?(String) ? data : JSON.generate(data)
          ::MCP::Tool::Response.new([ { type: "text", text: } ])
        end

        def error_response(message)
          ::MCP::Tool::Response.new([ { type: "text", text: message } ], error: true)
        end

        def paginated_text_response(result)
          data = result.is_a?(Hash) && result.key?("data") ? result["data"] : result
          meta = result.is_a?(Hash) ? result["meta"] : nil
          response_text = JSON.generate(data)
          response_text += "\n\nPage #{meta["page"]}, per_page: #{meta["per_page"]}, has_more: #{meta["has_more"]}" if meta
          text_response(response_text)
        end
      end
    end
  end
end
