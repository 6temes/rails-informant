require "json"
require "rails/generators"
require "rails_informant/claude_integration_content"

module RailsInformant
  class SkillGenerator < Rails::Generators::Base
    Content = ClaudeIntegrationContent

    source_root File.expand_path("skill/templates", __dir__)

    def copy_skill_file
      copy_file "SKILL.md", ".claude/skills/informant/SKILL.md"
    end

    def copy_hook_script
      copy_file "informant-alerts.sh", ".claude/hooks/informant-alerts.sh"
      chmod ".claude/hooks/informant-alerts.sh", 0o755
    end

    def create_or_update_mcp_json
      mcp_path = File.join(destination_root, ".mcp.json")

      if File.exist?(mcp_path)
        existing = JSON.parse(File.read(mcp_path))
        existing["mcpServers"] ||= {}
        existing["mcpServers"]["informant"] = Content.mcp_entry
        create_file ".mcp.json", JSON.pretty_generate(existing) + "\n", force: true
      else
        create_file ".mcp.json", JSON.pretty_generate(
          "mcpServers" => { "informant" => Content.mcp_entry }
        ) + "\n"
      end
    rescue JSON::ParserError
      say "Could not parse existing .mcp.json — skipping merge. Add the informant server manually.", :red
    end

    def create_or_update_settings_json
      settings_path = File.join(destination_root, ".claude", "settings.json")

      if File.exist?(settings_path)
        existing = JSON.parse(File.read(settings_path))
        existing["hooks"] = migrate_informant_hooks(existing["hooks"])
        existing["hooks"][Content::HOOK_EVENT] ||= []
        existing["hooks"][Content::HOOK_EVENT] << Content.hook_registration
        create_file ".claude/settings.json", JSON.pretty_generate(existing) + "\n", force: true
      else
        create_file ".claude/settings.json", JSON.pretty_generate(
          "hooks" => Content.expected_registrations
        ) + "\n"
      end
    rescue JSON::ParserError
      say "Could not parse existing .claude/settings.json — skipping hook setup.", :red
    end

    def clear_drift_flag
      RailsInformant::Integration.new(app_root: destination_root).write_drift_flag stale: false
    end

    def print_next_steps
      say ""
      say "Claude Code integration installed!", :green
      say ""
      say "  Created .mcp.json"
      say "  Created .claude/skills/informant/SKILL.md"
      say "  Created .claude/hooks/informant-alerts.sh"
      say "  Created .claude/settings.json (UserPromptSubmit hook)"
      say ""
      say "Next step — set env vars so the MCP server and startup alerts can reach your app.", :yellow
      say "Add to your .envrc (or export manually):"
      say ""
      say "  export INFORMANT_PRODUCTION_URL=https://your-app.com"
      say "  export INFORMANT_PRODUCTION_TOKEN=<same token from credentials>"
      say ""
      say "The token must match rails_informant.api_token in your Rails credentials."
      say "Add .envrc to .gitignore — it contains secrets."
      say ""
      say "Optional: install jq for startup error alerts (brew install jq)", :cyan
    end

    private

    # Remove every prior informant registration (matched by script path) from all
    # event keys and drop keys left empty, so a re-run migrates a stale
    # registration (e.g. a leftover SessionStart from an earlier gem version)
    # instead of adding a second one alongside it. Unrelated hooks are preserved.
    # Self-heals across future event-key changes rather than hardcoding an event.
    def migrate_informant_hooks(hooks)
      hooks = {} unless hooks.is_a?(Hash)
      hooks.each_value do |entries|
        entries.reject! { |entry| Content.informant_hook_entry?(entry) } if entries.is_a?(Array)
      end
      hooks.reject! { |_event, entries| entries.is_a?(Array) && entries.empty? }
      hooks
    end
  end
end
