require "net/http"
require "json"
require "uri"

module RailsInformant
  module Mcp
    class Client
      Error = Class.new(StandardError)

      METHODS = {
        delete: Net::HTTP::Delete,
        get: Net::HTTP::Get,
        patch: Net::HTTP::Patch,
        post: Net::HTTP::Post
      }.freeze

      def initialize(url:, token:, allow_insecure: false, path_prefix: "/informant")
        @base_url = url.chomp("/")
        @token = token
        @allow_insecure = allow_insecure
        @path_prefix = path_prefix.chomp("/")
        @_base_uri = URI.parse(@base_url)
        validate_url!
      end

      def list_errors(status: nil, error_class: nil, q: nil, since: nil, page: nil, per_page: nil, controller_action: nil, job_class: nil, severity: nil, **extra)
        params = { controller_action:, error_class:, job_class:, q:, severity:, since:, status:, page:, per_page: }
        params[:until] = extra[:until] if extra[:until]
        perform :get, "#{@path_prefix}/api/v1/errors", params: params.compact
      end

      def get_error(id)
        perform :get, "#{@path_prefix}/api/v1/errors/#{Integer(id)}"
      end

      def update_error(id, params)
        perform :patch, "#{@path_prefix}/api/v1/errors/#{Integer(id)}", body: params
      end

      def delete_error(id)
        perform :delete, "#{@path_prefix}/api/v1/errors/#{Integer(id)}"
      end

      def fix_pending(id, fix_sha:, original_sha:, fix_pr_url: nil)
        perform :patch, "#{@path_prefix}/api/v1/errors/#{Integer(id)}/fix_pending", body: { fix_sha:, original_sha:, fix_pr_url: }.compact
      end

      def mark_duplicate(id, duplicate_of_id:)
        perform :patch, "#{@path_prefix}/api/v1/errors/#{Integer(id)}/duplicate", body: { duplicate_of_id: }
      end

      def list_occurrences(error_group_id: nil, since: nil, page: nil, per_page: nil, **extra)
        params = { error_group_id:, since:, page:, per_page: }
        params[:until] = extra[:until] if extra[:until]
        perform :get, "#{@path_prefix}/api/v1/occurrences", params: params.compact
      end

      def notify_deploy(sha:)
        perform :post, "#{@path_prefix}/api/v1/deploy", body: { sha: }
      end

      def status
        perform :get, "#{@path_prefix}/api/v1/status"
      end

      private

      def validate_url!
        return if @allow_insecure
        raise Error, "HTTPS required. Use --allow-insecure for local development." unless @_base_uri.scheme == "https"
      end

      def perform(method, path, params: {}, body: nil)
        uri = build_uri(path, params)
        klass = METHODS.fetch(method) { raise ArgumentError, "Unsupported HTTP method: #{method}" }
        req = klass.new(uri)
        if body
          req.body = JSON.generate(body)
          req["Content-Type"] = "application/json"
        end
        execute(req)
      end

      def build_uri(path, params = {})
        uri = URI.parse("#{@base_url}#{path}")
        uri.query = URI.encode_www_form(params) unless params.empty?
        uri
      end

      def connection
        @_connection ||= begin
          http = Net::HTTP.new(@_base_uri.host, @_base_uri.port)
          http.use_ssl = @_base_uri.scheme == "https"
          http.open_timeout = 5
          http.read_timeout = 10
          http.start
        end
      end

      def execute(req)
        req["Authorization"] = "Bearer #{@token}"

        response = connection.request(req)

        case response
        when Net::HTTPSuccess
          response.body&.empty? ? nil : JSON.parse(response.body)
        when Net::HTTPUnauthorized
          raise Error, "Authentication failed. Check your API token."
        when Net::HTTPNotFound
          raise Error, "Not found (404)"
        else
          body = JSON.parse(response.body)
          raise Error, body["error"] || "HTTP #{response.code}"
        end
      rescue JSON::ParserError
        raise Error, "HTTP #{response.code}: #{response.body.to_s[0, 200]}"
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, SocketError => e
        @_connection = nil
        raise Error, "Connection failed: #{e.message}"
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        @_connection = nil
        raise Error, "Request timed out: #{e.message}"
      end
    end
  end
end
