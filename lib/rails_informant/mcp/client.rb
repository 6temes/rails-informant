require "net/http"
require "json"
require "uri"

module RailsInformant
  module Mcp
    class Client
      Error = Class.new(StandardError)

      def initialize(url:, token:, allow_insecure: false)
        @base_url = url.chomp("/")
        @token = token
        @allow_insecure = allow_insecure
        validate_url!
      end

      def list_errors(status: nil, error_class: nil, q: nil, since: nil, page: nil, per_page: nil, **extra)
        params = { status:, error_class:, q:, since:, page:, per_page: }
        params[:until] = extra[:until] if extra[:until]
        get "/informant/api/errors", params.compact
      end

      def get_error(id)
        get "/informant/api/errors/#{id}"
      end

      def update_error(id, params)
        patch "/informant/api/errors/#{id}", params
      end

      def delete_error(id)
        perform :delete, "/informant/api/errors/#{id}"
      end

      def fix_pending(id, fix_sha:, original_sha:, fix_pr_url: nil)
        post "/informant/api/errors/#{id}/fix_pending", { fix_sha:, original_sha:, fix_pr_url: }.compact
      end

      def mark_duplicate(id, duplicate_of_id:)
        post "/informant/api/errors/#{id}/duplicate", { duplicate_of_id: }
      end

      def list_occurrences(error_group_id: nil, since: nil, page: nil, per_page: nil, **extra)
        params = { error_group_id:, since:, page:, per_page: }
        params[:until] = extra[:until] if extra[:until]
        get "/informant/api/occurrences", params.compact
      end

      def status
        get "/informant/api/status"
      end

      private

      def validate_url!
        uri = URI.parse(@base_url)
        return if @allow_insecure
        raise Error, "HTTPS required. Use --allow-insecure for local development." unless uri.scheme == "https"
      end

      def get(path, params = {})
        uri = build_uri(path, params)
        req = Net::HTTP::Get.new(uri)
        execute(uri, req)
      end

      def post(path, body = {})
        uri = build_uri(path)
        req = Net::HTTP::Post.new(uri)
        req.body = JSON.generate(body)
        req["Content-Type"] = "application/json"
        execute(uri, req)
      end

      def patch(path, body = {})
        uri = build_uri(path)
        req = Net::HTTP::Patch.new(uri)
        req.body = JSON.generate(body)
        req["Content-Type"] = "application/json"
        execute(uri, req)
      end

      def perform(method, path)
        uri = build_uri(path)
        req = Net::HTTP.const_get(method.to_s.capitalize).new(uri)
        execute(uri, req)
      end

      def build_uri(path, params = {})
        uri = URI.parse("#{@base_url}#{path}")
        uri.query = URI.encode_www_form(params) unless params.empty?
        uri
      end

      def execute(uri, req)
        req["Authorization"] = "Bearer #{@token}"

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 10
        http.read_timeout = 30

        response = http.request(req)

        case response
        when Net::HTTPSuccess
          response.body&.empty? ? nil : JSON.parse(response.body)
        when Net::HTTPUnauthorized
          raise Error, "Authentication failed. Check your API token."
        when Net::HTTPNotFound
          raise Error, "Not found (404)"
        else
          body = begin; JSON.parse(response.body); rescue; {}; end
          raise Error, body["error"] || "HTTP #{response.code}"
        end
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
        raise Error, "Connection failed: #{e.message}"
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        raise Error, "Request timed out: #{e.message}"
      end
    end
  end
end
