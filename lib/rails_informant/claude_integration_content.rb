require "json"

module RailsInformant
  # Single source of truth for the generated Claude Code integration content.
  #
  # Both SkillGenerator (generation) and Integration (drift detection) build
  # their fragments here so the two can never silently diverge. Intentionally
  # free of any rails/generators (Thor) dependency: Integration runs on the
  # host-app boot path via the engine initializer, which must not load Thor.
  module ClaudeIntegrationContent
    # Paths, relative to the host app root, of the files the generator writes.
    HOOK_SCRIPT_PATH = ".claude/hooks/informant-alerts.sh"
    SKILL_PATH = ".claude/skills/informant/SKILL.md"
    SETTINGS_PATH = ".claude/settings.json"
    MCP_PATH = ".mcp.json"

    # The command string a settings.json hook entry uses to invoke the script.
    # Match-by-path detection keys on this value across every event key.
    HOOK_COMMAND = HOOK_SCRIPT_PATH

    # The event key the current gem registers the hook under.
    HOOK_EVENT = "UserPromptSubmit"

    module_function

    # Directory of the installed gem, resolved from RubyGems rather than a
    # generator's source_root so it works on the host-app boot path. Never
    # RailsInformant::VERSION — that constant is env-driven and resolves to the
    # 0.0.0.dev fallback in host apps.
    def gem_dir
      Gem.loaded_specs["rails-informant"].gem_dir
    end

    def templates_dir
      File.join gem_dir, "lib", "generators", "rails_informant", "skill", "templates"
    end

    def hook_script
      File.read File.join(templates_dir, "informant-alerts.sh")
    end

    def skill_markdown
      File.read File.join(templates_dir, "SKILL.md")
    end

    # The informant server entry inside .mcp.json's "mcpServers".
    def mcp_entry
      { "command" => "informant-mcp" }
    end

    # A single UserPromptSubmit hook registration for settings.json.
    def hook_registration(command = HOOK_COMMAND)
      {
        "hooks" => [
          { "type" => "command", "command" => command, "timeout" => 10 }
        ]
      }
    end

    # The informant-owned hooks map the generator produces: the registration
    # keyed by its event. Detection compares the host app's extracted informant
    # registrations against this, so a leftover entry under a different event key
    # (e.g. a stale SessionStart) reads as drift.
    def expected_registrations
      { HOOK_EVENT => [ hook_registration ] }
    end

    # Whether a settings.json hook entry targets the informant script — the
    # shared match-by-path predicate used by both generation (to sweep stale
    # registrations) and detection (to extract the informant fragment).
    def informant_hook_entry?(entry, command = HOOK_COMMAND)
      entry.is_a?(Hash) && Array(entry["hooks"]).any? do |hook|
        hook.is_a?(Hash) && hook["command"] == command
      end
    end
  end
end
