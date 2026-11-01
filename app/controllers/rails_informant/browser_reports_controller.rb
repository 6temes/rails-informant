module RailsInformant
  # Receives reports from the browser module. It does not inherit the API
  # base controller: pages post here with no token, so the trust boundary is
  # the same-origin check, and every field in the body is attacker-controlled.
  class BrowserReportsController < ActionController::API
    MAX_BODY_BYTES = 64.kilobytes
    MAX_REPORTS = 10

    # rate_limit captures its store when the class loads, so this reads the
    # controller's cache_store per request instead; under a null store the
    # limit is inert.
    module LiveCacheStore
      def self.increment(...) = BrowserReportsController.cache_store.increment(...)
    end

    class_attribute :schema_warning_logged, default: false

    include SecurityHeaders

    # Parameter wrapping would parse the body before the size check.
    wrap_parameters false

    # Instrumentation parses a JSON body and logs it as Parameters before any
    # callback runs, so a declared oversize body is refused ahead of it.
    def process_action(...)
      return head :content_too_large if request.content_length.to_i > MAX_BODY_BYTES

      super
    end

    before_action :verify_same_origin!
    rate_limit to: 30, within: 1.minute, store: LiveCacheStore, with: -> { head :too_many_requests }
    before_action :require_browser_schema!
    before_action { Current.ingesting_browser_report = true }

    def create
      body = request.body.read(MAX_BODY_BYTES + 1).to_s
      return head :content_too_large if body.bytesize > MAX_BODY_BYTES

      reports = parse_reports(body) or return head :bad_request

      reports.first(MAX_REPORTS).each do |report|
        next unless report.is_a?(Hash) && report.key?("name") && report.key?("message")

        ErrorRecorder.record_browser report,
          base_url: request.base_url,
          context: BrowserContext.verify(report["context"]),
          remote_ip: request.remote_ip,
          user_agent: request.user_agent
      end

      head :no_content
    end

    private

    # Browsers set both headers and pages cannot forge them. Without
    # Sec-Fetch-Site (older browsers), Origin must name this app exactly.
    def verify_same_origin!
      fetch_site = request.headers["Sec-Fetch-Site"]
      same_origin = fetch_site ? fetch_site == "same-origin" : request.origin == request.base_url
      head :forbidden unless same_origin
    end

    def require_browser_schema!
      return if RailsInformant.browser_schema_ready?

      unless schema_warning_logged
        self.class.schema_warning_logged = true
        Rails.logger.warn "[RailsInformant] Browser reports rejected: run `bin/rails generate rails_informant:browser` and migrate to add the browser capture columns"
      end
      head :service_unavailable
    end

    def parse_reports(body)
      payload = JSON.parse(body)
      payload["reports"] if payload.is_a?(Hash) && payload.key?("v") && payload["reports"].is_a?(Array)
    rescue JSON::ParserError
      nil
    end
  end
end
