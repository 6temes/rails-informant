require "rails/generators"

module RailsInformant
  class SkillGenerator < Rails::Generators::Base
    source_root File.expand_path("skill/templates", __dir__)

    def copy_skill_file
      copy_file "SKILL.md", ".claude/skills/informant/SKILL.md"
      say "Installed /informant skill to .claude/skills/informant/SKILL.md", :green
    end
  end
end
