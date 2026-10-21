require "test_helper"
require "rails/hyperdrive/bundler_artifact_discovery"

class RailsInformant::HyperdriveDiscoveryTest < ActiveSupport::TestCase
  Discovery = Rails::Hyperdrive::BundlerArtifactDiscovery

  test "discovers exactly the informant skill, installed at the path the generator uses" do
    report = Discovery::Report.new
    skills = Discovery.discover(specs: [ Gem.loaded_specs["rails-informant"] ], report: report).select(&:skill?)

    assert_equal [ "informant" ], skills.map(&:name)
    assert_equal RailsInformant::ClaudeIntegrationContent::SKILL_PATH, Rails::Hyperdrive::InstallLayout.dest_for(:skill, skills.first.name)
    assert_empty report.skips
  end

  test "loads discovery without mounting the Hyperdrive engine" do
    assert_not defined?(Rails::Hyperdrive::Engine)
  end
end
