module RailsInformant
  class Event
    attr_reader :error, :error_class, :message, :controller_action, :job_class, :request_path, :source
    attr_accessor :fingerprint, :severity

    def initialize(error, attributes, env: nil, fingerprint: nil, request_path: env&.dig("PATH_INFO"), source: "server")
      @error = error
      @error_class = attributes[:error_class]
      @message = attributes[:message]
      @severity = attributes[:severity]
      @controller_action = attributes[:controller_action]
      @job_class = attributes[:job_class]
      @request_path = request_path
      @fingerprint = fingerprint
      @source = source
      @halted = false
    end

    def halt!
      @halted = true
    end

    def halted?
      @halted
    end
  end
end
