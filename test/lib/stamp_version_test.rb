require "test_helper"
require "open3"

class RailsInformant::StampVersionTest < ActiveSupport::TestCase
  ROOT = File.expand_path("../..", __dir__)
  SCRIPT = File.join(ROOT, "bin", "stamp-version")

  setup do
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "version.rb")
    FileUtils.cp File.join(ROOT, "lib", "rails_informant", "version.rb"), @path
  end

  teardown do
    FileUtils.remove_entry @dir
  end

  test "stamps the tag version into the real version.rb" do
    _, status = stamp "1.2.3"

    assert status.success?
    assert_equal "1.2.3", loaded_version
  end

  test "rejects a version that is not canonical, leaving the file unchanged" do
    original = File.read(@path)

    [ "abc", "", "1.2.3-rc1" ].each do |version|
      stderr, status = stamp version

      assert_not status.success?, "accepted #{version.inspect}"
      assert_match(/not a canonical gem version/, stderr)
      assert_equal original, File.read(@path)
    end
  end

  test "rejects a file without a VERSION literal, leaving it unchanged" do
    File.write @path, "module RailsInformant\nend\n"

    stderr, status = stamp "1.2.3"

    assert_not status.success?
    assert_match(/expected one VERSION literal/, stderr)
    assert_equal "module RailsInformant\nend\n", File.read(@path)
  end

  private
    def stamp(version)
      _, stderr, status = Open3.capture3(RbConfig.ruby, SCRIPT, version, @path)
      [ stderr, status ]
    end

    # Loaded in a separate process so the suite's own RailsInformant::VERSION
    # is never redefined.
    def loaded_version
      stdout, _, status = Open3.capture3(RbConfig.ruby, "-e", "load ARGV[0]; print RailsInformant::VERSION", @path)
      assert status.success?
      stdout
    end
end
