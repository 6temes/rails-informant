require "digest"

module RailsInformant
  class Fingerprint
    APP_FRAME_PATTERN = /\A(?!.*\/(gems|ruby|rubies)\/)/.freeze

    def self.generate(exception, context: {})
      if RailsInformant.custom_fingerprint
        custom = RailsInformant.custom_fingerprint.call(exception, context)
        return custom if custom
      end

      first_frame = first_app_frame(exception)
      normalized = normalize_frame(first_frame)
      Digest::SHA256.hexdigest "#{exception.class.name}:#{normalized}"
    end

    def self.first_app_frame(exception)
      return nil unless exception.backtrace

      exception.backtrace.find { APP_FRAME_PATTERN.match?(_1) } || exception.backtrace.first
    end

    def self.normalize_frame(frame)
      return "" unless frame
      frame.sub(/:\d+/, ":0")
    end
  end
end
