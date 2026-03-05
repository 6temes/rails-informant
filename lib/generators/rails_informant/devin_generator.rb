require "rails/generators"

module RailsInformant
  class DevinGenerator < Rails::Generators::Base
    source_root File.expand_path("devin/templates", __dir__)

    def copy_playbook
      copy_file "error-triage.devin.md", ".devin/error-triage.devin.md"
    end

    def print_next_steps
      say ""
      say "Devin AI integration installed!", :green
      say ""
      say "  Created .devin/error-triage.devin.md"
      say ""
      say "Next steps — configure the MCP server in Devin:", :yellow
      say "  1. Go to Settings > MCP Marketplace in the Devin web app"
      say "  2. Click \"Add Your Own\""
      say "  3. Fill in:"
      say "       Name:        Rails Informant"
      say "       Transport:   STDIO"
      say "       Command:     informant-mcp"
      say "       Env vars:    INFORMANT_PRODUCTION_URL=https://your-app.com"
      say "                    INFORMANT_PRODUCTION_TOKEN=<same token from credentials>"
      say "  4. Click \"Test listing tools\" to verify the connection"
      say ""
      say "The token must match rails_informant.api_token in your Rails credentials."
      say ""
    end
  end
end
