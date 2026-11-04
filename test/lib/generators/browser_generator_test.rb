require "test_helper"
require "rails/generators/test_case"
require "generators/rails_informant/browser_generator"

class RailsInformant::BrowserGeneratorTest < Rails::Generators::TestCase
  tests RailsInformant::BrowserGenerator
  destination File.expand_path("../../tmp/browser_generator_test", __dir__)

  INITIALIZER = "config/initializers/rails_informant.rb"
  LAYOUT = "app/views/layouts/application.html.erb"
  MIGRATION = "db/migrate/add_browser_capture_to_informant_tables.rb"

  # Written by the install generator before browser capture existed: no flag line.
  PRE_BROWSER_INITIALIZER = <<~RUBY
    RailsInformant.configure do |config|
      config.capture_errors = !Rails.env.local?

      config.api_token = Rails.application.credentials.dig(:rails_informant, :api_token)

      # Auto-purge resolved errors after N days (nil = keep forever)
      # config.retention_days = 30
    end
  RUBY

  setup do
    prepare_destination
    write "config/importmap.rb", <<~RUBY
      pin "application"
      pin "@hotwired/turbo-rails", to: "turbo.min.js"
    RUBY
    write LAYOUT, <<~ERB
      <!DOCTYPE html>
      <html>
        <head>
          <title>Dummy</title>
          <%= csrf_meta_tags %>
          <%= stylesheet_link_tag "application" %>
          <%= javascript_importmap_tags %>
        </head>
        <body><%= yield %></body>
      </html>
    ERB
    write INITIALIZER, File.read(File.expand_path("../../../lib/generators/rails_informant/templates/initializer.rb.erb", __dir__))
  end

  test "writes the migration, pin, layout tag and flag in one run" do
    without_browser_columns { run_generator }

    assert_migration MIGRATION do |content|
      assert_includes content, "class AddBrowserCaptureToInformantTables"
      assert_includes content, "add_column :informant_error_groups, :source"
    end
    assert_file "config/importmap.rb" do |content|
      assert_equal 1, content.scan(/^pin "rails_informant"$/).count
    end
    assert_file LAYOUT do |content|
      assert_includes content, "    <%= informant_browser_tag %>\n    <%= javascript_importmap_tags %>\n"
    end
    assert_file INITIALIZER do |content|
      assert_match(/^  config\.capture_browser_errors = true$/, content)
      assert_no_match(/# config\.capture_browser_errors/, content)
    end
  end

  test "a second run changes no file and writes no second migration" do
    without_browser_columns { run_generator }
    before = snapshot

    without_browser_columns { run_generator }

    assert_equal before, snapshot
    assert_equal 1, Dir[File.join(destination_root, "db/migrate/*.rb")].size
  end

  test "skips the migration when the connected database already has the columns" do
    output = run_generator

    assert_no_migration MIGRATION
    assert_match(/already has the browser capture columns/, output)
  end

  test "adds the flag inside the configure block of an initializer that predates it" do
    write INITIALIZER, PRE_BROWSER_INITIALIZER

    without_browser_columns { run_generator }

    expected = PRE_BROWSER_INITIALIZER.sub(/^end\n\z/, "  config.capture_browser_errors = true\nend\n")
    assert_file(INITIALIZER) { assert_equal expected, it }

    without_browser_columns { run_generator }

    assert_file(INITIALIZER) { assert_equal expected, it }
  end

  test "leaves an initializer that already sets the flag alone" do
    configured = PRE_BROWSER_INITIALIZER.sub("config.capture_errors", "config.capture_browser_errors = Rails.env.production?\n  config.capture_errors")
    write INITIALIZER, configured

    without_browser_columns { run_generator }

    assert_file(INITIALIZER) { assert_equal configured, it }
  end

  test "places the tag before </head> when the layout has no importmap tags" do
    write LAYOUT, <<~ERB
      <html>
        <head>
          <title>Dummy</title>
        </head>
      </html>
    ERB

    without_browser_columns { run_generator }

    assert_file LAYOUT do |content|
      assert_includes content, "    <%= informant_browser_tag %>\n  </head>\n"
    end
  end

  test "inserts nothing into a layout that already has the tag" do
    layout = <<~ERB
      <html>
        <head>
          <%= javascript_importmap_tags %>
        <%= informant_browser_tag %>
        </head>
      </html>
    ERB
    write LAYOUT, layout

    without_browser_columns { run_generator }

    assert_file(LAYOUT) { assert_equal layout, it }
  end

  test "reports a missing importmap and still writes the other changes" do
    FileUtils.rm File.join(destination_root, "config/importmap.rb")

    output = without_browser_columns { run_generator }

    assert_match(/config\/importmap\.rb not found/, output)
    assert_no_file "config/importmap.rb"
    assert_migration MIGRATION
    assert_file(LAYOUT) { assert_includes it, "informant_browser_tag" }
    assert_file(INITIALIZER) { assert_match(/^  config\.capture_browser_errors = true$/, it) }
  end

  test "reports a missing layout and initializer" do
    FileUtils.rm File.join(destination_root, LAYOUT)
    FileUtils.rm File.join(destination_root, INITIALIZER)

    output = without_browser_columns { run_generator }

    assert_match(/#{Regexp.escape LAYOUT} not found/, output)
    assert_match(/#{Regexp.escape INITIALIZER} not found/, output)
    assert_file("config/importmap.rb") { assert_includes it, %(pin "rails_informant") }
  end

  test "prints next steps" do
    output = without_browser_columns { run_generator }

    assert_match(/bin\/rails db:migrate/, output)
    assert_match(/[Rr]estart/, output)
  end

  private

  def snapshot
    Dir[File.join(destination_root, "**/*")].select { File.file? it }.sort.to_h { [ it, File.read(it) ] }
  end

  # The dummy app's test schema already has the columns, which is the "already
  # migrated" case; most tests need the upgrade case instead.
  def without_browser_columns(&)
    ActiveRecord::Base.connection.stubs(:column_exists?).returns(false)
    yield
  ensure
    ActiveRecord::Base.connection.unstub(:column_exists?)
  end

  def write(relative_path, content)
    path = File.join(destination_root, relative_path)
    FileUtils.mkdir_p File.dirname(path)
    File.write path, content
  end
end
