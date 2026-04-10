require "ipaddr"
require "net/http"
require "json"
require "resolv"
require "uri"

module RailsInformant
  module Notifiers
    module NotificationPolicy
      COOLDOWN = 1.hour
      MILESTONE_COUNTS = [ 10, 100, 1000 ].freeze
      SILENT_STATUSES = %w[duplicate ignored].freeze

      PRIVATE_NETWORKS = [
        IPAddr.new("0.0.0.0/8"),       # "This" network
        IPAddr.new("10.0.0.0/8"),       # RFC 1918
        IPAddr.new("100.64.0.0/10"),    # Carrier-grade NAT
        IPAddr.new("127.0.0.0/8"),      # Loopback
        IPAddr.new("169.254.0.0/16"),   # Link-local
        IPAddr.new("172.16.0.0/12"),    # RFC 1918
        IPAddr.new("192.0.0.0/24"),     # IETF protocol assignments
        IPAddr.new("192.0.2.0/24"),     # TEST-NET-1
        IPAddr.new("192.168.0.0/16"),   # RFC 1918
        IPAddr.new("198.18.0.0/15"),    # Benchmarking
        IPAddr.new("198.51.100.0/24"),  # TEST-NET-2
        IPAddr.new("203.0.113.0/24"),   # TEST-NET-3
        IPAddr.new("240.0.0.0/4"),      # Reserved
        IPAddr.new("::1/128"),          # IPv6 loopback
        IPAddr.new("fc00::/7"),         # IPv6 unique local
        IPAddr.new("fe80::/10")         # IPv6 link-local
      ].freeze

      def should_notify?(error_group)
        return false if error_group.status.in?(SILENT_STATUSES)
        return true if error_group.total_occurrences == 1
        return true if error_group.total_occurrences.in?(MILESTONE_COUNTS)
        return true if error_group.last_notified_at.nil?
        return true if error_group.last_notified_at < COOLDOWN.ago

        false
      end

      private

      # SSRF safety: We resolve DNS upfront and connect directly to the validated IP.
      # Never enable redirect following — a redirect to an internal IP would bypass this protection.
      # max_retries is set to 0 to prevent automatic retries that would re-resolve DNS.
      def post_json(url:, body:, headers: {}, label: "HTTP")
        uri = URI.parse url
        raise ArgumentError, "#{label} URL must use HTTPS" unless uri.scheme == "https"

        resolved_ip = resolve_and_validate_public!(uri.hostname, label:)

        request = Net::HTTP::Post.new uri, { "Content-Type" => "application/json", "Host" => uri.hostname }.merge(headers)
        request.body = body.to_json

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, ipaddr: resolved_ip, open_timeout: 10, read_timeout: 15, max_retries: 0) do |http|
          http.request request
        end

        unless response.is_a?(Net::HTTPSuccess)
          raise RailsInformant::NotifierError, "#{label} error: HTTP #{response.code} — #{response.body&.to_s&.truncate(200)}"
        end

        response
      end

      def resolve_and_validate_public!(hostname, label: "HTTP")
        addresses = Resolv.getaddresses hostname

        raise ArgumentError, "#{label} URL host could not be resolved" if addresses.empty?

        addresses.each do |addr|
          ip = IPAddr.new addr
          ip = ip.native if ip.ipv4_mapped?
          if PRIVATE_NETWORKS.any? { it.include? ip }
            raise ArgumentError, "#{label} URL must not target private network (#{hostname} resolved to #{addr})"
          end
        end

        addresses.first
      end
    end
  end
end
