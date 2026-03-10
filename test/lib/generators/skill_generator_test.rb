require "test_helper"
require "rails/generators/test_case"
require "generators/rails_informant/skill_generator"

class RailsInformant::SkillGeneratorTest < Rails::Generators::TestCase
  tests RailsInformant::SkillGenerator
  destination File.expand_path("../../tmp/generator_test", __dir__)

  setup do
    prepare_destination
  end

  test "creates skill file" do
    run_generator

    assert_file ".claude/skills/informant/SKILL.md"
  end

  test "creates hook script with executable permissions" do
    run_generator

    assert_file ".claude/hooks/informant-alerts.sh" do |content|
      assert_match "#!/usr/bin/env bash", content
      assert_match "INFORMANT_PRODUCTION_URL", content
      assert_match "INFORMANT_PRODUCTION_TOKEN", content
      assert_match "jq", content
    end

    script_path = File.join(destination_root, ".claude/hooks/informant-alerts.sh")
    assert File.executable?(script_path), "Hook script should be executable"
  end

  test "hook script is syntactically valid" do
    run_generator

    script_path = File.join(destination_root, ".claude/hooks/informant-alerts.sh")
    assert system("bash", "-n", script_path), "Hook script has syntax errors"
  end

  test "creates .mcp.json with informant server" do
    run_generator

    assert_file ".mcp.json" do |content|
      config = JSON.parse(content)
      assert_equal "informant-mcp", config.dig("mcpServers", "informant", "command")
    end
  end

  test "creates settings.json with SessionStart hook" do
    run_generator

    assert_file ".claude/settings.json" do |content|
      settings = JSON.parse(content)
      hooks = settings.dig("hooks", "SessionStart")
      assert_not_nil hooks
      assert_equal 1, hooks.length
      assert_equal "startup", hooks.first["matcher"]
      assert_equal ".claude/hooks/informant-alerts.sh", hooks.first.dig("hooks", 0, "command")
      assert_equal 10, hooks.first.dig("hooks", 0, "timeout")
    end
  end

  test "merges into existing settings.json without clobbering" do
    mkdir_p ".claude"
    File.write File.join(destination_root, ".claude/settings.json"), JSON.pretty_generate(
      "allowedTools" => [ "Read", "Write" ],
      "hooks" => {
        "PreToolUse" => [ { "matcher" => "Edit", "hooks" => [ { "type" => "command", "command" => "lint.sh" } ] } ]
      }
    )

    run_generator

    assert_file ".claude/settings.json" do |content|
      settings = JSON.parse(content)
      # Existing settings preserved
      assert_equal [ "Read", "Write" ], settings["allowedTools"]
      # Existing hooks preserved
      assert_not_nil settings.dig("hooks", "PreToolUse")
      # New hook added
      session_hooks = settings.dig("hooks", "SessionStart")
      assert_equal 1, session_hooks.length
      assert_equal ".claude/hooks/informant-alerts.sh", session_hooks.first.dig("hooks", 0, "command")
    end
  end

  test "idempotent — re-running does not duplicate hook entries" do
    run_generator
    run_generator

    assert_file ".claude/settings.json" do |content|
      settings = JSON.parse(content)
      hooks = settings.dig("hooks", "SessionStart")
      assert_equal 1, hooks.length
    end
  end

  test "handles malformed settings.json gracefully" do
    mkdir_p ".claude"
    File.write File.join(destination_root, ".claude/settings.json"), "not valid json {"

    output = run_generator

    assert_match(/Could not parse/, output)
  end

  test "merges into existing .mcp.json without clobbering" do
    File.write File.join(destination_root, ".mcp.json"), JSON.pretty_generate(
      "mcpServers" => { "other" => { "command" => "other-mcp" } }
    )

    run_generator

    assert_file ".mcp.json" do |content|
      config = JSON.parse(content)
      assert_equal "other-mcp", config.dig("mcpServers", "other", "command")
      assert_equal "informant-mcp", config.dig("mcpServers", "informant", "command")
    end
  end

  private

  def mkdir_p(relative_path)
    FileUtils.mkdir_p File.join(destination_root, relative_path)
  end
end
