require "rails_informant/integration"

module RailsInformant
  # The informant:doctor channel: reports the integration state, prints the fix,
  # refreshes the drift flag, and returns a process exit code (nonzero on stale
  # or error) so it doubles as a CI signal. A thin wrapper over Integration that
  # never raises out — a diagnostic must not crash the run it reports on.
  class Doctor
    def initialize(integration: Integration.new, io: $stdout)
      @integration = integration
      @io = io
    end

    def run
      status = @integration.status
      @integration.write_drift_flag stale: status == :stale
      @io.puts report_for(status)
      exit_code_for status
    rescue StandardError => e
      # An unexpected failure must exit nonzero, not 0 — a doctor wired into CI
      # to gate drift must never report a false green when it could not check.
      @io.puts "[Informant] doctor could not complete: #{e.message}"
      1
    end

    private

    def report_for(status)
      case status
      when :current
        "[Informant] Claude Code integration is up to date."
      when :not_installed
        "[Informant] Claude Code integration is not installed — nothing to check."
      when :stale
        <<~REPORT.chomp
          [Informant] Claude Code integration is OUT OF DATE.
          The installed gem would generate different .claude/ files than this app has committed.
          Fix: bin/rails g rails_informant:skill
        REPORT
      when :error
        <<~REPORT.chomp
          [Informant] Claude Code integration could not be verified.
          .claude/settings.json or .mcp.json is present but is not valid JSON.
          Fix that file by hand — re-running the generator skips unparseable files.
        REPORT
      end
    end

    def exit_code_for(status)
      status == :stale || status == :error ? 1 : 0
    end
  end
end
