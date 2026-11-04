require "digest"

module RailsInformant
  class BrowserFingerprint
    HEX = /\b(?:0x)?(?=[0-9a-f]*\d)[0-9a-f]{8,}\b/i
    URL = %r{\b[a-z][a-z0-9+.-]*://\S+}i
    UUID = /\b\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\b/

    # The message is left out when an app frame exists because browsers word
    # the same failure differently, which would split one bug into a group
    # per engine.
    def self.generate(error_class:, message:, stack:)
      key = stack.first_app_frame&.fingerprint_key || normalize_message(message)
      Digest::SHA256.hexdigest "browser:#{error_class}:#{key}"
    end

    def self.normalize_message(message)
      message.to_s.gsub(URL, "<url>").gsub(UUID, "<uuid>").gsub(HEX, "<hex>").gsub(/\d+/, "<n>")
    end
  end
end
