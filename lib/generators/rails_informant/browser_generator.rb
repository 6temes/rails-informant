require "rails/generators"
require "rails/generators/active_record"

module RailsInformant
  class BrowserGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration

    HEAD_CLOSE_LINE = /^([ \t]*)<\/head>/
    IMPORTMAP = "config/importmap.rb"
    IMPORTMAP_TAGS_LINE = /^([ \t]*)<%=\s*javascript_importmap_tags/
    INITIALIZER = "config/initializers/rails_informant.rb"
    LAYOUT = "app/views/layouts/application.html.erb"
    TAG = "<%= informant_browser_tag %>"

    source_root File.expand_path("templates", __dir__)

    def create_migration_file
      if browser_columns_present?
        say "Database already has the browser capture columns, skipping the migration.", :yellow
        return
      end

      migration_template "add_browser_capture_to_informant_tables.rb.erb",
        "db/migrate/add_browser_capture_to_informant_tables.rb"
    end

    def pin_module
      return say_missing(IMPORTMAP, %(add `pin "rails_informant"` to your import map)) unless exist?(IMPORTMAP)
      return if read(IMPORTMAP).match?(/^\s*pin\s+["']rails_informant["']/)

      separator = read(IMPORTMAP).end_with?("\n") ? "" : "\n"
      append_to_file IMPORTMAP, %(#{separator}pin "rails_informant"\n)
    end

    def add_layout_tag
      return say_missing(LAYOUT, "add #{TAG} to your layout's <head>, before javascript_importmap_tags") unless exist?(LAYOUT)

      layout = read(LAYOUT)
      return if layout.include?("informant_browser_tag")

      if (indent = layout[IMPORTMAP_TAGS_LINE, 1])
        inject_into_file LAYOUT, "#{indent}#{TAG}\n", before: IMPORTMAP_TAGS_LINE
      elsif (indent = layout[HEAD_CLOSE_LINE, 1])
        inject_into_file LAYOUT, "#{indent}  #{TAG}\n", before: HEAD_CLOSE_LINE
      else
        say "No javascript_importmap_tags or </head> in #{LAYOUT}. Add #{TAG} to your layout's <head> manually.", :red
      end
    end

    def enable_capture
      return say_missing(INITIALIZER, "set `config.capture_browser_errors = true` in your RailsInformant.configure block") unless exist?(INITIALIZER)

      initializer = read(INITIALIZER)
      commented = /^([ \t]*)#\s*(config\.capture_browser_errors = true)$/

      if initializer.match?(commented)
        gsub_file INITIALIZER, commented, '\1\2'
      elsif initializer.include?("capture_browser_errors")
        nil
      elsif (block = initializer.match(/^RailsInformant\.configure do \|(\w+)\|\n.*?(?=^end\b)/m))
        inject_into_file INITIALIZER, "  #{block[1]}.capture_browser_errors = true\n", after: block[0]
      else
        say "No RailsInformant.configure block in #{INITIALIZER}. Set config.capture_browser_errors = true manually.", :red
      end
    end

    def print_next_steps
      say ""
      say "Browser error capture set up!", :green
      say ""
      say "Next steps:", :yellow
      say "  1. Run migrations:"
      say "       bin/rails db:migrate"
      say ""
      say "  2. Restart the app server."
      say ""
      say "  3. Load a page and check the browser console and network panel"
      say "     for the rails_informant module."
      say ""
    end

    private

    # No connection or no informant tables yet (install migration not run) both
    # count as "absent": the migration's own guards make writing it harmless.
    def browser_columns_present?
      connection = ActiveRecord::Base.connection
      connection.column_exists?(:informant_error_groups, :source) &&
        connection.column_exists?(:informant_occurrences, :request_id) &&
        connection.column_exists?(:informant_occurrences, :failing_request_id)
    rescue ActiveRecord::ActiveRecordError
      false
    end

    def exist?(relative_path) = File.exist?(File.join(destination_root, relative_path))

    def read(relative_path) = File.read(File.join(destination_root, relative_path))

    def say_missing(relative_path, instruction)
      say "#{relative_path} not found, skipping. #{instruction.upcase_first}.", :red
    end
  end
end
