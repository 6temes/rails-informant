module RailsInformant
  class Event
    attr_reader :error, :error_class, :message, :controller_action, :job_class, :request_path
    attr_accessor :fingerprint, :severity

    def initialize(error, attributes, env: nil, fingerprint: nil)
      @error = error
      @error_class = attributes[:error_class]
      @message = attributes[:message]
      @severity = attributes[:severity]
      @controller_action = attributes[:controller_action]
      @job_class = attributes[:job_class]
      @request_path = env&.dig("PATH_INFO")
      @fingerprint = fingerprint
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
