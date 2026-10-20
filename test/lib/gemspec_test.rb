require "test_helper"

class RailsInformant::GemspecTest < ActiveSupport::TestCase
  setup do
    @spec = Gem::Specification.load File.expand_path("../../rails-informant.gemspec", __dir__)
  end

  test "packages the skill at the Hyperdrive companion path" do
    assert_includes @spec.files, "skills/informant/SKILL.md"
    assert_empty @spec.files.grep(%r{\Atest/})
  end

  test "opts in as a Hyperdrive companion for apps that bundle the gem" do
    assert_equal "rails-informant", @spec.metadata["hyperdrive_targets"]
  end
end
