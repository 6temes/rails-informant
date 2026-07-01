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

    assert_file ".claude/hooks/informant-alerts.sh"

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

  test "creates settings.json with UserPromptSubmit hook" do
    run_generator

    assert_file ".claude/settings.json" do |content|
      settings = JSON.parse(content)
      assert_nil settings.dig("hooks", "SessionStart")
      hooks = settings.dig("hooks", "UserPromptSubmit")
      assert_not_nil hooks
      assert_equal 1, hooks.length
      assert_nil hooks.first["matcher"]
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
      prompt_hooks = settings.dig("hooks", "UserPromptSubmit")
      assert_equal 1, prompt_hooks.length
      assert_equal ".claude/hooks/informant-alerts.sh", prompt_hooks.first.dig("hooks", 0, "command")
    end
  end

  test "idempotent — re-running does not duplicate hook entries" do
    run_generator
    run_generator

    assert_file ".claude/settings.json" do |content|
      settings = JSON.parse(content)
      hooks = settings.dig("hooks", "UserPromptSubmit")
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

  test "migrates a stale SessionStart informant registration to UserPromptSubmit" do
    write_settings "hooks" => { "SessionStart" => [ informant_hook_entry ] }

    run_generator

    assert_file ".claude/settings.json" do |content|
      settings = JSON.parse(content)
      assert_nil settings.dig("hooks", "SessionStart"), "the stale SessionStart key should be gone"
      user_prompt_submit = settings.dig("hooks", "UserPromptSubmit")
      assert_equal 1, user_prompt_submit.length
      assert_equal ".claude/hooks/informant-alerts.sh", user_prompt_submit.first.dig("hooks", 0, "command")
    end
  end

  test "preserves an unrelated hook under SessionStart while migrating the informant entry" do
    write_settings "hooks" => {
      "SessionStart" => [
        { "hooks" => [ { "type" => "command", "command" => "other-tool.sh" } ] },
        informant_hook_entry
      ]
    }

    run_generator

    assert_file ".claude/settings.json" do |content|
      settings = JSON.parse(content)
      session_start = settings.dig("hooks", "SessionStart")
      assert_equal 1, session_start.length, "the unrelated SessionStart hook must survive"
      assert_equal "other-tool.sh", session_start.first.dig("hooks", 0, "command")
      assert_equal 1, settings.dig("hooks", "UserPromptSubmit").length
    end
  end

  test "removes a stale informant registration under any event key" do
    write_settings "hooks" => { "PostToolUse" => [ informant_hook_entry ] }

    run_generator

    assert_file ".claude/settings.json" do |content|
      settings = JSON.parse(content)
      assert_nil settings.dig("hooks", "PostToolUse")
      assert_equal 1, settings.dig("hooks", "UserPromptSubmit").length
    end
  end

  test "clears the drift flag after generating" do
    flag = File.join(destination_root, "tmp", "rails-informant-drift")
    FileUtils.mkdir_p File.dirname(flag)
    File.write flag, "stale"

    run_generator

    assert_not File.exist?(flag), "generating should clear the drift flag"
  end

  test "generated integration is byte-identical to what Integration considers current" do
    run_generator

    integration = RailsInformant::Integration.new(app_root: destination_root)
    assert_equal :current, integration.status,
      "the generator's output must match the installed gem's expected content"
  end

  test "coerces a hand-written non-array event value instead of crashing" do
    write_settings "hooks" => { "UserPromptSubmit" => { "type" => "command" } }

    assert_nothing_raised { run_generator }

    assert_file ".claude/settings.json" do |content|
      hooks = JSON.parse(content).dig("hooks", "UserPromptSubmit")
      assert_kind_of Array, hooks
      assert_equal 1, hooks.length
      assert_equal ".claude/hooks/informant-alerts.sh", hooks.first.dig("hooks", 0, "command")
    end
  end

  private

  def informant_hook_entry
    { "hooks" => [ { "type" => "command", "command" => ".claude/hooks/informant-alerts.sh", "timeout" => 10 } ] }
  end

  def write_settings(data)
    mkdir_p ".claude"
    File.write File.join(destination_root, ".claude/settings.json"), JSON.pretty_generate(data)
  end

  def mkdir_p(relative_path)
    FileUtils.mkdir_p File.join(destination_root, relative_path)
  end
end
