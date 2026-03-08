require_relative "test_helper"

module RailsInformant
  module Mcp
    class ServerTest < Minitest::Test
      def setup
        @config = mock("config")
      end

      def test_build_returns_mcp_server
        server = Server.build(@config)
        assert_kind_of ::MCP::Server, server
      end

      def test_build_includes_instructions
        server = Server.build(@config)
        refute_nil server.instructions
      end
    end
  end
end
