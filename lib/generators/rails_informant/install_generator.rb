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
  end
end
