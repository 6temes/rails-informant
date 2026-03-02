require_relative "test_helper"

module RailsInformant
  module Mcp
    class ClientTest < Minitest::Test
      def setup
        @client = Client.new(url: "https://app.example.com", token: "test-token")
      end

      def test_reuses_persistent_connection
        http = stub_connection
        http.expects(:request).twice.returns(success_response)

        @client.status
        @client.status
      end

      def test_wraps_connection_refused_in_client_error
        stub_connection_start_raises Errno::ECONNREFUSED, "Connection refused"

        error = assert_raises(Client::Error) { @client.status }
        assert_match(/Connection failed/, error.message)
      end

      def test_wraps_timeout_in_client_error
        stub_connection_start_raises Net::OpenTimeout, "timed out"

        error = assert_raises(Client::Error) { @client.status }
        assert_match(/timed out/, error.message)
      end

      def test_wraps_socket_error_in_client_error
        stub_connection_start_raises SocketError, "getaddrinfo: Name does not resolve"

        error = assert_raises(Client::Error) { @client.status }
        assert_match(/Connection failed/, error.message)
      end

      def test_get_error_rejects_non_integer_id
        assert_raises(ArgumentError) { @client.get_error("1/../../admin") }
      end

      def test_update_error_rejects_non_integer_id
        assert_raises(ArgumentError) { @client.update_error("1/../../admin", { status: "resolved" }) }
      end

      def test_delete_error_rejects_non_integer_id
        assert_raises(ArgumentError) { @client.delete_error("1/../../admin") }
      end

      def test_fix_pending_rejects_non_integer_id
        assert_raises(ArgumentError) { @client.fix_pending("1/../../admin", fix_sha: "abc", original_sha: "def") }
      end

      def test_mark_duplicate_rejects_non_integer_id
        assert_raises(ArgumentError) { @client.mark_duplicate("1/../../admin", duplicate_of_id: 2) }
      end

      def test_accepts_string_integer_id
        http = stub_connection
        http.stubs(:request).returns(success_response('{"id":42}'))
        @client.get_error("42")
      end

      def test_resets_connection_on_connection_refused
        http = stub_connection
        http.stubs(:request).raises(Errno::ECONNREFUSED, "Connection refused").then.returns(success_response)

        assert_raises(Client::Error) { @client.status }

        # Second call should create a fresh connection (not reuse the stale one)
        http2 = stub_connection
        http2.stubs(:request).returns(success_response)
        assert_equal({ "status" => "ok" }, @client.status)
      end

      def test_resets_connection_on_timeout
        http = stub_connection
        http.stubs(:request).raises(Net::ReadTimeout, "timed out").then.returns(success_response)

        assert_raises(Client::Error) { @client.status }

        http2 = stub_connection
        http2.stubs(:request).returns(success_response)
        assert_equal({ "status" => "ok" }, @client.status)
      end

      def test_resets_connection_on_connection_reset
        http = stub_connection
        http.stubs(:request).raises(Errno::ECONNRESET, "Connection reset").then.returns(success_response)

        assert_raises(Client::Error) { @client.status }

        http2 = stub_connection
        http2.stubs(:request).returns(success_response)
        assert_equal({ "status" => "ok" }, @client.status)
      end

      def test_custom_path_prefix
        client = Client.new(url: "https://app.example.com", token: "test-token", path_prefix: "/errors")
        http = stub_connection
        http.expects(:request).with { |req| req.path == "/errors/api/v1/status" }.returns(success_response)

        client.status
      end

      def test_default_path_prefix
        http = stub_connection
        http.expects(:request).with { |req| req.path == "/informant/api/v1/status" }.returns(success_response)

        @client.status
      end

      private

      def stub_connection
        http = stub("http", use_ssl: true, open_timeout: 5, read_timeout: 10)
        http.stubs(:use_ssl=)
        http.stubs(:open_timeout=)
        http.stubs(:read_timeout=)
        http.stubs(:start).returns(http)
        Net::HTTP.stubs(:new).with("app.example.com", 443).returns(http)
        http
      end

      def stub_connection_start_raises(error_class, message)
        http = stub("http")
        http.stubs(:use_ssl=)
        http.stubs(:open_timeout=)
        http.stubs(:read_timeout=)
        http.stubs(:start).raises(error_class, message)
        Net::HTTP.stubs(:new).with("app.example.com", 443).returns(http)
        http
      end

      def success_response(body = '{"status":"ok"}')
        response = Net::HTTPSuccess.new("1.1", "200", "OK")
        response.stubs(:body).returns(body)
        response
      end
    end
  end
end
