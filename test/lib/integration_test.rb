require "test_helper"
require "open3"
require "tmpdir"
require "fileutils"

class RailsInformant::IntegrationTest < ActiveSupport::TestCase
  Content = RailsInformant::ClaudeIntegrationContent

  setup do
    @app_root = Pathname.new(Dir.mktmpdir)
  end

  teardown do
    FileUtils.remove_entry @app_root if @app_root && File.directory?(@app_root)
  end

  test "byte-identical live files are current" do
    install_current

    assert_equal :current, integration.status
    assert integration.installed?
    assert_not integration.stale?
  end

  test "hook script differing from the gem template is stale" do
    install_current
    hook_file.write "#!/usr/bin/env bash\necho tampered\n"

    assert_equal :stale, integration.status
    assert integration.stale?
  end

  test "informant registration under a different event key is stale" do
    install_current
    write_settings "hooks" => { "SessionStart" => [ Content.hook_registration ] }

    assert_equal :stale, integration.status
  end

  test "hook script deleted while an informant entry remains is stale" do
    install_current
    hook_file.delete

    assert integration.installed?, "an .mcp.json informant entry still marks it installed"
    assert_equal :stale, integration.status
  end

  test "no hook script and no informant entry is not_installed" do
    assert_equal :not_installed, integration.status
    assert_not integration.installed?
  end

  test "an app with unrelated .claude files but no informant is not_installed" do
    write_settings "hooks" => { "PreToolUse" => [ { "matcher" => "Edit", "hooks" => [ { "command" => "lint.sh" } ] } ] }
    write_json mcp_file, "mcpServers" => { "other" => { "command" => "other-mcp" } }

    assert_equal :not_installed, integration.status
  end

  test "present-but-unparseable settings.json is error, not stale, and does not raise" do
    install_current
    settings_file.write "not valid json {"

    assert_nothing_raised { integration.status }
    assert_equal :error, integration.status
  end

  test "present-but-unparseable .mcp.json is error" do
    install_current
    mcp_file.write "{ broken"

    assert_equal :error, integration.status
  end

  test "hook differing only by CRLF and trailing whitespace is current" do
    install_current
    crlf = Content.hook_script.gsub("\n", "  \r\n") + "\r\n\r\n"
    hook_file.write crlf

    assert_equal :current, integration.status, "line-ending / trailing-whitespace noise must normalize away"
  end

  test "a leading UTF-8 BOM on a text file is current (BOM stripped)" do
    install_current
    bom = [ 0xFEFF ].pack("U")
    skill_file.write bom + Content.skill_markdown

    assert_equal :current, integration.status, "a leading BOM must normalize away"
  end

  test "gem_version reads from Gem.loaded_specs, not the VERSION constant" do
    spec = Gem::Specification.new { |s| s.version = "9.9.9" }
    Gem.stubs(:loaded_specs).returns("rails-informant" => spec)

    assert_equal "9.9.9", integration.gem_version
    assert_not_equal RailsInformant::VERSION, integration.gem_version
  end

  test "digest is deterministic and independent of JSON key order" do
    install_current
    first = digest

    # Rewrite settings with the hook entry's inner keys in a different order.
    reordered = { "timeout" => 10, "command" => Content::HOOK_COMMAND, "type" => "command" }
    write_settings "hooks" => { "UserPromptSubmit" => [ { "hooks" => [ reordered ] } ] }

    assert_equal first, digest, "reordering keys in the live JSON fragment must not change the digest"
  end

  test "write_drift_flag creates and removes the flag under tmp" do
    integration.write_drift_flag stale: true
    assert File.exist?(@app_root.join("tmp", "rails-informant-drift"))

    integration.write_drift_flag stale: false
    assert_not File.exist?(@app_root.join("tmp", "rails-informant-drift"))
  end

  test "write_drift_flag does not raise when the flag cannot be written" do
    integration.stubs(:drift_flag_path).raises(Errno::EACCES)

    assert_nothing_raised { integration.write_drift_flag(stale: true) }
  end

  test "the primitive and shared module load without rails/generators or Thor" do
    # Runs in a fresh process — the full suite loads rails/generators elsewhere,
    # so an in-process check would pass for the wrong reason.
    lib = File.expand_path "../../lib", __dir__
    script = <<~RUBY
      $LOAD_PATH.unshift #{lib.inspect}
      require "rails_informant/integration"
      abort "rails/generators loaded" if defined?(Rails::Generators)
      abort "thor loaded" if defined?(Thor)
    RUBY
    output, status = Open3.capture2e RbConfig.ruby, "-e", script

    assert status.success?, "loading Integration pulled in generators/Thor: #{output}"
  end

  private

  def integration
    RailsInformant::Integration.new app_root: @app_root
  end

  def digest
    integration.send :live_digest
  end

  def install_current
    hook_file.dirname.mkpath
    hook_file.write Content.hook_script
    skill_file.dirname.mkpath
    skill_file.write Content.skill_markdown
    write_settings "hooks" => Content.expected_registrations
    write_json mcp_file, "mcpServers" => { "informant" => Content.mcp_entry }
  end

  def write_settings(data)
    write_json settings_file, data
  end

  def write_json(path, data)
    path.dirname.mkpath
    path.write JSON.pretty_generate(data) + "\n"
  end

  def hook_file = @app_root.join(Content::HOOK_SCRIPT_PATH)
  def skill_file = @app_root.join(Content::SKILL_PATH)
  def settings_file = @app_root.join(Content::SETTINGS_PATH)
  def mcp_file = @app_root.join(Content::MCP_PATH)
end
