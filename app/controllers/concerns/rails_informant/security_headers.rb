module RailsInformant
  module SecurityHeaders
    extend ActiveSupport::Concern

    included do
      before_action :set_security_headers
    end

    private

    def set_security_headers
      response.headers["Cache-Control"] = "no-store"
      response.headers["Content-Security-Policy"] = "default-src 'none'"
      response.headers["X-Content-Type-Options"] = "nosniff"
      response.headers["X-Frame-Options"] = "DENY"
    end
  end
end
