require "json"
require "rails/generators"
require "rails/generators/active_record"

module RailsInformant
  class InstallGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration

    source_root File.expand_path("templates", __dir__)

    def create_migration_file
      migration_template "create_informant_tables.rb.erb",
        "db/migrate/create_informant_tables.rb"
    end

    def create_initializer
      template "initializer.rb.erb",
        "config/initializers/rails_informant.rb"
    end

    def mount_engine
      route "mount RailsInformant::Engine => '/informant'"
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
      say "Rails Informant installed!", :green
      say ""
      say "Next steps:", :yellow
      say "  1. Run migrations:"
      say "       bin/rails db:migrate"
      say ""
      say "  2. Set a token (required for MCP server access):"
      say "       bin/rails credentials:edit"
      say "       # Add: rails_informant:"
      say "       #        api_token: #{SecureRandom.hex 32}"
      say ""
      say "  3. Configure env vars for the MCP server (e.g., via .envrc + direnv):"
      say "       export INFORMANT_PRODUCTION_URL=https://your-app.com"
      say "       export INFORMANT_PRODUCTION_TOKEN=your-api-token"
      say ""
      say "     The token must match the api_token in your Rails credentials."
      say "     Add .envrc to .gitignore — it contains secrets."
      say ""
      say "  4. Optional — install the Claude Code skill:"
      say "       bin/rails generate rails_informant:skill"
      say ""
    end

    private

    def json_column_type
      adapter = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env).first&.adapter.to_s
      adapter.match?(/postgres/i) ? "jsonb" : "json"
    end
  end
end
