require "json"
require "rails/generators"

module RailsInformant
  class SkillGenerator < Rails::Generators::Base
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
      informant_entry = { "command" => "informant-mcp" }

      if File.exist?(mcp_path)
        existing = JSON.parse(File.read(mcp_path))
        existing["mcpServers"] ||= {}
        existing["mcpServers"]["informant"] = informant_entry
        create_file ".mcp.json", JSON.pretty_generate(existing) + "\n", force: true
      else
        create_file ".mcp.json", JSON.pretty_generate(
          "mcpServers" => { "informant" => informant_entry }
        ) + "\n"
      end
    rescue JSON::ParserError
      say "Could not parse existing .mcp.json — skipping merge. Add the informant server manually.", :red
    end

    def create_or_update_settings_json
      settings_path = File.join(destination_root, ".claude", "settings.json")
      hook_command = ".claude/hooks/informant-alerts.sh"

      if File.exist?(settings_path)
        existing = JSON.parse(File.read(settings_path))
        existing["hooks"] ||= {}
        existing["hooks"]["SessionStart"] ||= []

        already_registered = existing["hooks"]["SessionStart"].any? do |entry|
          entry["hooks"]&.any? { it["command"] == hook_command }
        end

        unless already_registered
          existing["hooks"]["SessionStart"] << session_start_hook(hook_command)
        end

        create_file ".claude/settings.json", JSON.pretty_generate(existing) + "\n", force: true
      else
        create_file ".claude/settings.json", JSON.pretty_generate(
          "hooks" => { "SessionStart" => [ session_start_hook(hook_command) ] }
        ) + "\n"
      end
    rescue JSON::ParserError
      say "Could not parse existing .claude/settings.json — skipping hook setup.", :red
    end

    def print_next_steps
      say ""
      say "Claude Code integration installed!", :green
      say ""
      say "  Created .mcp.json"
      say "  Created .claude/skills/informant/SKILL.md"
      say "  Created .claude/hooks/informant-alerts.sh"
      say "  Created .claude/settings.json (SessionStart hook)"
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
    end

    private

    def session_start_hook(command)
      {
        "matcher" => "startup",
        "hooks" => [
          { "type" => "command", "command" => command, "timeout" => 10 }
        ]
      }
    end
  end
end
