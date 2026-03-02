require_relative "lib/rails_informant/version"

Gem::Specification.new do |spec|
  spec.name = "rails-informant"
  spec.version = RailsInformant::VERSION
  spec.authors = [ "Daniel Lopez" ]
  spec.email = [ "daniel@example.com" ]
  spec.homepage = "https://github.com/dlopez/rails-informant"
  spec.summary = "Self-hosted error inbox for Rails + agent workflow"
  spec.description = "Captures errors, stores them in your app's database with rich debugging context, sends notifications, and exposes error data via a token-authenticated API consumed by a bundled MCP server."
  spec.license = "MIT"

  spec.required_ruby_version = ">= 4.0"

  spec.files = Dir.chdir(__dir__) do
    Dir["{app,config,db,exe,lib}/**/*", "LICENSE", "Rakefile", "README.md", "VERSION"]
  end

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }

  spec.add_dependency "actionpack", ">= 8.1"
  spec.add_dependency "activejob", ">= 8.1"
  spec.add_dependency "activerecord", ">= 8.1"
  spec.add_dependency "mcp", "~> 0.7"
  spec.add_dependency "railties", ">= 8.1"
end
