require "test_helper"
require "rails/generators/test_case"
require "generators/rails_informant/install_generator"

class RailsInformant::InstallGeneratorTest < Rails::Generators::TestCase
  tests RailsInformant::InstallGenerator
  destination File.expand_path("../../tmp/generator_test", __dir__)

  setup do
    prepare_destination
    mkdir_p "config"
    File.write File.join(destination_root, "config/routes.rb"), <<~RUBY
      Rails.application.routes.draw do
      end
    RUBY
  end

  test "creates migration file" do
    run_generator

    assert_migration "db/migrate/create_informant_tables.rb"
  end

  test "migration uses json column type" do
    run_generator

    assert_migration "db/migrate/create_informant_tables.rb" do |content|
      assert_includes content, "t.json :backtrace"
    end
  end

  test "creates initializer" do
    run_generator

    assert_file "config/initializers/rails_informant.rb"
  end

  test "initializer contains expected configuration" do
    run_generator

    assert_file "config/initializers/rails_informant.rb" do |content|
      assert_includes content, "RailsInformant.configure"
      assert_includes content, "config.api_token"
      assert_includes content, "config.capture_errors"
    end
  end

  test "mounts engine route" do
    run_generator

    assert_file "config/routes.rb" do |content|
      assert_includes content, 'mount RailsInformant::Engine => "/informant"'
    end
  end

  test "idempotent — re-running does not duplicate route" do
    run_generator
    run_generator

    assert_file "config/routes.rb" do |content|
      assert_equal 1, content.scan("RailsInformant::Engine").count
    end
  end

  test "prints next steps" do
    output = run_generator

    assert_match(/Rails Informant installed!/, output)
    assert_match(/Run migrations/, output)
    assert_match(/rails_informant:skill/, output)
  end

  private

  def mkdir_p(relative_path)
    FileUtils.mkdir_p File.join(destination_root, relative_path)
  end
end
