module RailsInformant
  module Mcp
    module ToolTestHelper
      def setup
        @client = Client.new(url: "https://test.example.com", token: "test-token")
        @config = mock("config")
        @config.stubs(:default_environment).returns("production")
        @config.stubs(:client_for).with("production").returns(@client)
        @server_context = { config: @config }
      end

      def paginated(data, page: 1, per_page: 20, has_more: false)
        { "data" => data, "meta" => { "page" => page, "per_page" => per_page, "has_more" => has_more } }
      end
    end
  end
end
