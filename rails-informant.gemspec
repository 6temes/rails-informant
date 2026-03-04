require_relative "lib/rails_informant/version"

Gem::Specification.new do |spec|
  spec.name = "rails-informant"
  spec.version = RailsInformant::VERSION
  spec.authors = [ "Daniel López Prat" ]
  spec.email = [ "daniel@6temes.cat" ]
  spec.homepage = "https://github.com/6temes/rails-informant"
  spec.summary = "Self-hosted error monitoring for Rails with MCP server for agentic workflows"
  spec.description = "Rails Engine that captures exceptions, stores them in your database with rich context, and exposes error data via a bundled MCP server so AI agents can triage, resolve, and fix errors autonomously."
  spec.license = "MIT"

  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/6temes/rails-informant/issues",
    "changelog_uri" => "https://github.com/6temes/rails-informant/releases",
    "rubygems_mfa_required" => "true",
    "source_code_uri" => "https://github.com/6temes/rails-informant"
  }

  spec.required_ruby_version = ">= 4.0"

  spec.files = Dir.chdir(__dir__) do
    Dir["{app,config,db,exe,lib}/**/*", "LICENSE", "Rakefile", "README.md", "VERSION"]
  end

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }

  spec.add_dependency "actionpack", ">= 8.1"
  spec.add_dependency "activejob", ">= 8.1"
  spec.add_dependency "activerecord", ">= 8.1"
  spec.add_dependency "activesupport", ">= 8.1"
  spec.add_dependency "railties", ">= 8.1"
end
