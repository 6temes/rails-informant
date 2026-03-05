require "json"
require "rails/generators"

module RailsInformant
  class SkillGenerator < Rails::Generators::Base
    source_root File.expand_path("skill/templates", __dir__)

    def copy_skill_file
      copy_file "SKILL.md", ".claude/skills/informant/SKILL.md"
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
    end

    def print_next_steps
      say ""
      say "Claude Code integration installed!", :green
      say ""
      say "  Created .mcp.json"
      say "  Created .claude/skills/informant/SKILL.md"
      say ""
      say "Next step — set env vars so the MCP server can reach your app.", :yellow
      say "Add to your .envrc (or export manually):"
      say ""
      say "  export INFORMANT_PRODUCTION_URL=https://your-app.com"
      say "  export INFORMANT_PRODUCTION_TOKEN=<same token from credentials>"
      say ""
      say "The token must match rails_informant.api_token in your Rails credentials."
      say "Add .envrc to .gitignore — it contains secrets."
      say ""
    end
  end
end
