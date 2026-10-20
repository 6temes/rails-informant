require "bundler/gem_tasks"
require "rake/testtask"
require "hyperdrive/skill_tasks"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.verbose = false
end

task default: :test
