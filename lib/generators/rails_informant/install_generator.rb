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
  end
end
