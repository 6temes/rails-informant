require "test_helper"
require "open3"
require "tmpdir"

class StampVersionTest < ActiveSupport::TestCase
  ROOT = File.expand_path("../..", __dir__)
  SCRIPT = File.join(ROOT, "bin/stamp-version")
  VERSION_FILE = File.join(ROOT, "lib/rails_informant/version.rb")

  setup do
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "version.rb")
    FileUtils.cp VERSION_FILE, @path
  end

  teardown do
    FileUtils.remove_entry @dir
  end

  test "the placeholder satisfies the >= 0 requirement Bundler gives a git source" do
    assert_operator Gem::Version.new(RailsInformant::VERSION), :>=, Gem::Version.new("0")
  end

  test "stamps the version into a copy of the real version.rb" do
    _, status = stamp "1.2.3"

    assert status.success?
    assert_equal "1.2.3", loaded_version
  end

  test "rejects a version that is not canonical, leaving the file unchanged" do
    original = File.read(@path)

    [ "abc", "", "1.2.3-rc1" ].each do |version|
      stderr, status = stamp version

      assert_not status.success?, "accepted #{version.inspect}"
      assert_match "is not a canonical gem version", stderr
      assert_equal original, File.read(@path)
    end
  end

  test "rejects a file without a VERSION literal, leaving it unchanged" do
    File.write @path, "module Foo\nend\n"

    stderr, status = stamp "1.2.3"

    assert_not status.success?
    assert_match "expected one VERSION literal", stderr
    assert_equal "module Foo\nend\n", File.read(@path)
  end

  test "rejects a file that does not load as the stamped version, leaving it unchanged" do
    [
      ->(placeholder) { "=begin\n#{placeholder}=end\n" },
      ->(placeholder) { "#{placeholder}VERSION = \"9.9.9\" # release version\n" },
      # Prints the tag's head first, so a check that read the child's output would pass.
      ->(placeholder) { "#{placeholder}print \"1.\"\nVERSION = \"2.3\".freeze\n" }
    ].each do |rewrite|
      source = File.read(VERSION_FILE).sub(/^\s*VERSION = .*\n/) { rewrite.(it) }
      File.write @path, source

      stderr, status = stamp "1.2.3"

      assert_not status.success?, "stamped #{source.inspect}"
      assert_match "does not load as", stderr
      assert_equal source, File.read(@path)
    end
  end

  private
    def stamp(version)
      _, stderr, status = Open3.capture3(RbConfig.ruby, SCRIPT, version, @path)
      [ stderr, status ]
    end

    # A child process without bundler, so this suite's own constant is never redefined.
    def loaded_version
      stdout, status = Open3.capture2({ "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil }, RbConfig.ruby, "-e", "load ARGV[0]; print RailsInformant::VERSION", @path)
      assert status.success?
      stdout
    end
end
