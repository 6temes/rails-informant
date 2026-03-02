require "digest"

module RailsInformant
  class Fingerprint
    APP_FRAME_PATTERN = /\A(?!.*\/(gems|ruby|rubies)\/)/.freeze

    def self.generate(exception)
      return Digest::SHA256.hexdigest(exception.class.name) unless exception.backtrace

      first_frame = first_app_frame(exception)
      normalized = normalize_frame(first_frame)
      Digest::SHA256.hexdigest "#{exception.class.name}:#{normalized}"
    end

    def self.first_app_frame(exception)
      exception.backtrace.find { APP_FRAME_PATTERN.match?(it) } || exception.backtrace.first
    end

    def self.normalize_frame(frame)
      frame.sub(/:(\d+)(?=:in |$)/, ":0")
    end
  end
end
