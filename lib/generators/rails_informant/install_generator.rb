require "rails/generators"
require "rails/generators/active_record"

module RailsInformant
  class InstallGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration

    source_root File.expand_path("templates", __dir__)

    def create_migration
      migration_template "create_informant_tables.rb.erb",
        "db/migrate/create_informant_tables.rb"
    end

    def create_initializer
      template "initializer.rb.erb",
        "config/initializers/rails_informant.rb"
    end

    def install_skill
      skill_source = File.expand_path("../../rails_informant/skill/SKILL.md", __dir__)
      skill_dest = ".claude/skills/informant/SKILL.md"

      copy_file skill_source, skill_dest
      say "Installed /informant skill to #{skill_dest}", :green
    end

    def install_devin_playbook
      playbook_source = File.expand_path("../../rails_informant/devin/error-triage.devin.md", __dir__)
      playbook_dest = ".devin/error-triage.devin.md"

      copy_file playbook_source, playbook_dest
      say "Installed Devin playbook to #{playbook_dest}", :green
    end
  end
end
