require "test_helper"

class RailsInformant::Notifiers::NotificationPolicyTest < ActiveSupport::TestCase
  setup do
    @notifier = PolicyTestNotifier.new
  end

  # HTTPS scheme enforcement

  test "rejects HTTP URL" do
    error = assert_raises(ArgumentError) do
      @notifier.send_post url: "http://example.com/hook"
    end
    assert_includes error.message, "must use HTTPS"
  end

  test "rejects URL with no scheme" do
    assert_raises(ArgumentError) do
      @notifier.send_post url: "example.com/hook"
    end
  end

  # Private network host rejection

  test "rejects localhost" do
    Resolv.stubs(:getaddresses).with("localhost").returns([ "127.0.0.1" ])

    error = assert_raises(ArgumentError) do
      @notifier.send_post url: "https://localhost/hook"
    end
    assert_includes error.message, "private network"
  end

  test "rejects 127.x.x.x loopback" do
    Resolv.stubs(:getaddresses).with("loopback.example.com").returns([ "127.0.0.1" ])

    error = assert_raises(ArgumentError) do
      @notifier.send_post url: "https://loopback.example.com/hook"
    end
    assert_includes error.message, "private network"
  end

  test "rejects 10.x.x.x RFC 1918" do
    Resolv.stubs(:getaddresses).with("internal.example.com").returns([ "10.0.0.1" ])

    error = assert_raises(ArgumentError) do
      @notifier.send_post url: "https://internal.example.com/hook"
    end
    assert_includes error.message, "private network"
  end

  test "rejects 172.16.x.x RFC 1918" do
    Resolv.stubs(:getaddresses).with("internal.example.com").returns([ "172.16.0.1" ])

    error = assert_raises(ArgumentError) do
      @notifier.send_post url: "https://internal.example.com/hook"
    end
    assert_includes error.message, "private network"
  end

  test "rejects 192.168.x.x RFC 1918" do
    Resolv.stubs(:getaddresses).with("internal.example.com").returns([ "192.168.1.1" ])

    error = assert_raises(ArgumentError) do
      @notifier.send_post url: "https://internal.example.com/hook"
    end
    assert_includes error.message, "private network"
  end

  test "rejects 169.254.x.x link-local" do
    Resolv.stubs(:getaddresses).with("link-local.example.com").returns([ "169.254.1.1" ])

    error = assert_raises(ArgumentError) do
      @notifier.send_post url: "https://link-local.example.com/hook"
    end
    assert_includes error.message, "private network"
  end

  test "rejects 100.64.x.x carrier-grade NAT" do
    Resolv.stubs(:getaddresses).with("cgnat.example.com").returns([ "100.64.0.1" ])

    error = assert_raises(ArgumentError) do
      @notifier.send_post url: "https://cgnat.example.com/hook"
    end
    assert_includes error.message, "private network"
  end

  test "rejects 192.0.2.x TEST-NET-1" do
    Resolv.stubs(:getaddresses).with("testnet1.example.com").returns([ "192.0.2.1" ])

    error = assert_raises(ArgumentError) do
      @notifier.send_post url: "https://testnet1.example.com/hook"
    end
    assert_includes error.message, "private network"
  end

  test "rejects 198.18.x.x benchmarking" do
    Resolv.stubs(:getaddresses).with("bench.example.com").returns([ "198.18.0.1" ])

    error = assert_raises(ArgumentError) do
      @notifier.send_post url: "https://bench.example.com/hook"
    end
    assert_includes error.message, "private network"
  end

  test "rejects 198.51.100.x TEST-NET-2" do
    Resolv.stubs(:getaddresses).with("testnet2.example.com").returns([ "198.51.100.1" ])

    error = assert_raises(ArgumentError) do
      @notifier.send_post url: "https://testnet2.example.com/hook"
    end
    assert_includes error.message, "private network"
  end

  test "rejects 203.0.113.x TEST-NET-3" do
    Resolv.stubs(:getaddresses).with("testnet3.example.com").returns([ "203.0.113.1" ])

    error = assert_raises(ArgumentError) do
      @notifier.send_post url: "https://testnet3.example.com/hook"
    end
    assert_includes error.message, "private network"
  end

  test "rejects 240.x.x.x reserved" do
    Resolv.stubs(:getaddresses).with("reserved.example.com").returns([ "240.0.0.1" ])

    error = assert_raises(ArgumentError) do
      @notifier.send_post url: "https://reserved.example.com/hook"
    end
    assert_includes error.message, "private network"
  end

  test "rejects IPv6 loopback ::1" do
    Resolv.stubs(:getaddresses).with("ipv6-loopback.example.com").returns([ "::1" ])

    error = assert_raises(ArgumentError) do
      @notifier.send_post url: "https://ipv6-loopback.example.com/hook"
    end
    assert_includes error.message, "private network"
  end

  test "rejects IPv6 unique local fc00::/7" do
    Resolv.stubs(:getaddresses).with("ipv6-ula.example.com").returns([ "fd12::1" ])

    error = assert_raises(ArgumentError) do
      @notifier.send_post url: "https://ipv6-ula.example.com/hook"
    end
    assert_includes error.message, "private network"
  end

  test "rejects IPv6 link-local fe80::/10" do
    Resolv.stubs(:getaddresses).with("ipv6-ll.example.com").returns([ "fe80::1" ])

    error = assert_raises(ArgumentError) do
      @notifier.send_post url: "https://ipv6-ll.example.com/hook"
    end
    assert_includes error.message, "private network"
  end

  test "rejects IPv4-mapped IPv6 loopback ::ffff:127.0.0.1" do
    Resolv.stubs(:getaddresses).with("mapped.example.com").returns([ "::ffff:127.0.0.1" ])

    error = assert_raises(ArgumentError) do
      @notifier.send_post url: "https://mapped.example.com/hook"
    end
    assert_includes error.message, "private network"
  end

  test "rejects IPv4-mapped IPv6 private ::ffff:10.0.0.1" do
    Resolv.stubs(:getaddresses).with("mapped-rfc1918.example.com").returns([ "::ffff:10.0.0.1" ])

    error = assert_raises(ArgumentError) do
      @notifier.send_post url: "https://mapped-rfc1918.example.com/hook"
    end
    assert_includes error.message, "private network"
  end

  test "rejects when any resolved address is private" do
    Resolv.stubs(:getaddresses).with("mixed.example.com").returns([ "93.184.216.34", "127.0.0.1" ])

    error = assert_raises(ArgumentError) do
      @notifier.send_post url: "https://mixed.example.com/hook"
    end
    assert_includes error.message, "private network"
  end

  test "rejects unresolvable hostname" do
    Resolv.stubs(:getaddresses).with("nxdomain.example.com").returns([])

    error = assert_raises(ArgumentError) do
      @notifier.send_post url: "https://nxdomain.example.com/hook"
    end
    assert_includes error.message, "could not be resolved"
  end

  # Public host acceptance

  test "allows public IP address" do
    Resolv.stubs(:getaddresses).with("hooks.slack.com").returns([ "93.184.216.34" ])

    response = Net::HTTPOK.new("1.1", "200", "")
    response.stubs(:body).returns("ok")
    stub_http = StubHTTP.new(response)
    Net::HTTP.stubs(:start).with("93.184.216.34", 443, use_ssl: true, open_timeout: 10, read_timeout: 15, max_retries: 0).yields(stub_http).returns(response)

    assert_nothing_raised { @notifier.send_post url: "https://hooks.slack.com/test" }
  end

  test "connects to resolved IP and sets Host header" do
    Resolv.stubs(:getaddresses).with("hooks.slack.com").returns([ "93.184.216.34" ])

    response = Net::HTTPOK.new("1.1", "200", "")
    response.stubs(:body).returns("ok")
    stub_http = StubHTTP.new(response)

    connected_host = nil
    Net::HTTP.stubs(:start).with { |host, *| connected_host = host; true }.yields(stub_http).returns(response)

    @notifier.send_post url: "https://hooks.slack.com/test"

    assert_equal "93.184.216.34", connected_host
    assert_equal "hooks.slack.com", stub_http.captured_request["Host"]
  end

  test "prevents DNS rebinding by using resolved IP for connection" do
    # DNS resolves to public IP during validation, but would resolve to private IP
    # on second lookup. Since we connect to the resolved IP directly, the second
    # lookup never happens.
    Resolv.stubs(:getaddresses).with("attacker.example.com").returns([ "93.184.216.34" ])

    response = Net::HTTPOK.new("1.1", "200", "")
    response.stubs(:body).returns("ok")
    stub_http = StubHTTP.new(response)

    connected_host = nil
    Net::HTTP.stubs(:start).with { |host, *| connected_host = host; true }.yields(stub_http).returns(response)

    @notifier.send_post url: "https://attacker.example.com/hook"

    # Connection must go to the validated IP, not back to the hostname
    assert_equal "93.184.216.34", connected_host
  end

  # Label propagation

  test "includes label in HTTPS error message" do
    error = assert_raises(ArgumentError) do
      @notifier.send_post url: "http://example.com/hook", label: "Slack webhook"
    end
    assert_includes error.message, "Slack webhook URL must use HTTPS"
  end

  test "includes label in private network error message" do
    Resolv.stubs(:getaddresses).with("localhost").returns([ "127.0.0.1" ])

    error = assert_raises(ArgumentError) do
      @notifier.send_post url: "https://localhost/hook", label: "Webhook"
    end
    assert_includes error.message, "Webhook URL must not target private network"
  end

  private

  # Thin wrapper to expose the private post_json method for testing
  class PolicyTestNotifier
    include RailsInformant::Notifiers::NotificationPolicy

    def send_post(url:, label: "HTTP")
      post_json url:, body: { test: true }, label:
    end
  end
end
