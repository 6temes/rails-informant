require "test_helper"

class RailsInformant::InitializedTest < ActiveSupport::TestCase
  test "returns true when capture_errors enabled and pool connected" do
    assert RailsInformant.initialized?
  end

  test "returns false when capture_errors disabled" do
    RailsInformant.config.capture_errors = false
    assert_not RailsInformant.initialized?
  end

  test "caches result after first successful check" do
    assert RailsInformant.initialized?

    # After caching, connection_pool.connected? must not be called again
    ActiveRecord::Base.connection_pool.expects(:connected?).never
    assert RailsInformant.initialized?
  end

  test "reset_caches! clears the cached result" do
    assert RailsInformant.initialized?
    RailsInformant.reset_caches!

    # After reset, it should re-check the connection pool
    ActiveRecord::Base.connection_pool.expects(:connected?).returns(true)
    assert RailsInformant.initialized?
  end

  test "returns false when connection not established" do
    RailsInformant.reset_caches!
    ActiveRecord::Base.connection_pool.stubs(:connected?).raises(ActiveRecord::ConnectionNotEstablished)

    assert_not RailsInformant.initialized?
  end

  # -- current_git_sha / resolve_git_sha --

  test "current_git_sha returns ENV value when GIT_SHA is set" do
    RailsInformant.reset_caches!

    with_env("GIT_SHA" => "abc123env") do
      assert_equal "abc123env", RailsInformant.current_git_sha
    end
  end

  test "current_git_sha returns REVISION env var" do
    RailsInformant.reset_caches!

    with_env("REVISION" => "rev456") do
      assert_equal "rev456", RailsInformant.current_git_sha
    end
  end

  test "current_git_sha reads .git/HEAD ref and resolves it" do
    RailsInformant.reset_caches!

    with_env({}) do
      with_git_dir do |git_dir|
        FileUtils.mkdir_p git_dir.join("refs", "heads")
        File.write git_dir.join("HEAD"), "ref: refs/heads/main\n"
        File.write git_dir.join("refs", "heads", "main"), "deadbeef1234\n"

        assert_equal "deadbeef1234", RailsInformant.current_git_sha
      end
    end
  end

  test "current_git_sha returns detached HEAD sha directly" do
    RailsInformant.reset_caches!

    with_env({}) do
      with_git_dir do |git_dir|
        File.write git_dir.join("HEAD"), "deadbeef5678\n"

        assert_equal "deadbeef5678", RailsInformant.current_git_sha
      end
    end
  end

  test "current_git_sha returns nil when .git/HEAD is missing" do
    RailsInformant.reset_caches!

    with_env({}) do
      with_git_dir do |_git_dir|
        # Don't create HEAD file -- it should be missing
        assert_nil RailsInformant.current_git_sha
      end
    end
  end

  test "current_git_sha rejects path traversal in ref" do
    RailsInformant.reset_caches!

    with_env({}) do
      with_git_dir do |git_dir|
        File.write git_dir.join("HEAD"), "ref: ../../etc/passwd\n"

        assert_nil RailsInformant.current_git_sha
      end
    end
  end

  test "current_git_sha is memoized" do
    RailsInformant.reset_caches!

    with_env({}) do
      with_git_dir do |git_dir|
        File.write git_dir.join("HEAD"), "abc123\n"

        assert_equal "abc123", RailsInformant.current_git_sha

        # Remove the file to prove second call uses cached value
        File.delete git_dir.join("HEAD")
        assert_equal "abc123", RailsInformant.current_git_sha
      end
    end
  end

  test "retries after a failed check" do
    RailsInformant.reset_caches!

    # First call: pool not connected
    ActiveRecord::Base.connection_pool.stubs(:connected?).returns(false)
    assert_not RailsInformant.initialized?

    # Second call: pool now connected — should re-check since false was not cached
    ActiveRecord::Base.connection_pool.stubs(:connected?).returns(true)
    assert RailsInformant.initialized?
  end

  private

  # Temporarily sets env vars, clearing GIT_SHA_SOURCES keys by default,
  # clears the git sha memoization, then restores everything after the block.
  def with_env(vars = {})
    saved = {}
    all_keys = RailsInformant::GIT_SHA_SOURCES + vars.keys
    all_keys.uniq.each do |key|
      saved[key] = ENV[key]
      if vars.key?(key)
        ENV[key] = vars[key]
      else
        ENV.delete(key)
      end
    end
    clear_git_sha_cache!
    yield
  ensure
    saved.each do |key, val|
      if val.nil?
        ENV.delete(key)
      else
        ENV[key] = val
      end
    end
    clear_git_sha_cache!
  end

  def clear_git_sha_cache!
    RailsInformant.remove_instance_variable(:@_current_git_sha) if RailsInformant.instance_variable_defined?(:@_current_git_sha)
  end

  # Creates a temporary directory with a .git subdirectory and stubs
  # Rails.root to point there, so resolve_git_sha reads from the temp dir.
  def with_git_dir
    Dir.mktmpdir do |tmpdir|
      fake_root = Pathname.new(tmpdir)
      git_dir = fake_root.join(".git")
      FileUtils.mkdir_p git_dir
      Rails.stubs(:root).returns(fake_root)
      clear_git_sha_cache!
      yield git_dir
    end
  end
end
