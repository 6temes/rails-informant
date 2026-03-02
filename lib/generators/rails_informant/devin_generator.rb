require "rails/generators"

module RailsInformant
  class DevinGenerator < Rails::Generators::Base
    source_root File.expand_path("devin/templates", __dir__)

    def copy_playbook
      copy_file "error-triage.devin.md", ".devin/error-triage.devin.md"
      say "Installed Devin playbook to .devin/error-triage.devin.md", :green
    end
  end
end
