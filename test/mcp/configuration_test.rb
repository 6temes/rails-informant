require_relative "test_helper"
require "tmpdir"

module RailsInformant
  module Mcp
    class ConfigurationTest < Minitest::Test
      def test_raises_when_config_file_is_world_readable
        with_temp_config(mode: 0644) do |path|
          error = assert_raises(RuntimeError) do
            config = Configuration.allocate
            config.instance_variable_set(:@allow_insecure, false)
            config.send(:reject_insecure_permissions, path)
          end

          assert_includes error.message, "insecure permissions"
          assert_includes error.message, "0644"
          assert_includes error.message, "chmod 600 #{path}"
          assert_includes error.message, "--allow-insecure"
        end
      end

      def test_raises_when_config_file_is_group_readable
        with_temp_config(mode: 0640) do |path|
          error = assert_raises(RuntimeError) do
            config = Configuration.allocate
            config.instance_variable_set(:@allow_insecure, false)
            config.send(:reject_insecure_permissions, path)
          end

          assert_includes error.message, "insecure permissions"
          assert_includes error.message, "0640"
          assert_includes error.message, "chmod 600 #{path}"
        end
      end

      def test_warns_when_config_file_is_world_readable_with_allow_insecure
        with_temp_config(mode: 0644) do |path|
          warning = capture_stderr do
            config = Configuration.allocate
            config.instance_variable_set(:@allow_insecure, true)
            config.send(:reject_insecure_permissions, path)
          end

          assert_includes warning, "WARNING"
          assert_includes warning, "insecure permissions"
        end
      end

      def test_no_error_when_config_file_is_owner_only
        with_temp_config(mode: 0600) do |path|
          config = Configuration.allocate
          config.instance_variable_set(:@allow_insecure, false)
          config.send(:reject_insecure_permissions, path)
        end
      end

      def test_load_from_yaml_raises_for_world_readable_config
        with_temp_config(mode: 0644) do |path|
          assert_raises(RuntimeError) do
            swap_config_path(path) { Configuration.new }
          end
        end
      end

      def test_load_from_yaml_warns_for_world_readable_config_with_allow_insecure
        with_temp_config(mode: 0644) do |path|
          warning = capture_stderr do
            swap_config_path(path) { Configuration.new(allow_insecure: true) }
          end

          assert_includes warning, "insecure permissions"
        end
      end

      def test_safe_environments_excludes_tokens
        with_temp_config(mode: 0600) do |path|
          config = swap_config_path(path) { Configuration.new }

          config.safe_environments.each_value do |env|
            assert_equal [ :url ], env.keys
          end
        end
      end

      def test_safe_environments_includes_urls
        with_temp_config(mode: 0600) do |path|
          config = swap_config_path(path) { Configuration.new }

          assert_equal "https://app.example.com", config.safe_environments["production"][:url]
        end
      end

      def test_environment_names_returns_keys
        with_temp_config(mode: 0600) do |path|
          config = swap_config_path(path) { Configuration.new }

          assert_equal [ "production" ], config.environment_names
        end
      end

      def test_interpolate_resolves_informant_prefixed_vars
        ENV["INFORMANT_TEST_VALUE"] = "secret123"
        config = Configuration.allocate

        result = config.send(:interpolate, "prefix-${INFORMANT_TEST_VALUE}-suffix")

        assert_equal "prefix-secret123-suffix", result
      ensure
        ENV.delete("INFORMANT_TEST_VALUE")
      end

      def test_interpolate_ignores_non_informant_prefixed_vars
        ENV["SECRET_KEY"] = "should-not-leak"
        config = Configuration.allocate

        result = config.send(:interpolate, "prefix-${SECRET_KEY}-suffix")

        assert_equal "prefix-${SECRET_KEY}-suffix", result
      ensure
        ENV.delete("SECRET_KEY")
      end

      def test_load_from_yaml_only_interpolates_token
        ENV["INFORMANT_PROD_TOKEN"] = "resolved-secret"
        yaml_content = <<~YAML
          environments:
            production:
              url: "https://app.example.com"
              token: "${INFORMANT_PROD_TOKEN}"
        YAML

        with_temp_config(mode: 0600, content: yaml_content) do |path|
          config = swap_config_path(path) { Configuration.new }
          envs = config.send(:instance_variable_get, :@environments)

          assert_equal "resolved-secret", envs["production"][:token]
          assert_equal "https://app.example.com", envs["production"][:url]
        end
      ensure
        ENV.delete("INFORMANT_PROD_TOKEN")
      end

      def test_load_from_yaml_does_not_interpolate_url
        ENV["INFORMANT_PROD_TOKEN"] = "resolved-secret"
        yaml_content = <<~YAML
          environments:
            production:
              url: "https://prefix-${INFORMANT_PROD_TOKEN}.example.com"
              token: "static-token"
        YAML

        with_temp_config(mode: 0600, content: yaml_content) do |path|
          config = swap_config_path(path) { Configuration.new }
          envs = config.send(:instance_variable_get, :@environments)

          assert_equal "https://prefix-${INFORMANT_PROD_TOKEN}.example.com", envs["production"][:url]
          assert_equal "static-token", envs["production"][:token]
        end
      ensure
        ENV.delete("INFORMANT_PROD_TOKEN")
      end

      def test_no_public_environments_accessor
        refute Configuration.public_method_defined?(:environments),
          "Configuration should not expose environments publicly"
      end

      private

      def with_temp_config(mode:, content: nil)
        Dir.mktmpdir do |dir|
          path = File.join(dir, "informant-mcp.yml")
          File.write path, content || <<~YAML
            environments:
              production:
                url: https://app.example.com
                token: test-token
          YAML
          File.chmod mode, path

          yield path
        end
      end

      def swap_config_path(path)
        original = Configuration::CONFIG_PATH
        silence_warnings { Configuration.const_set(:CONFIG_PATH, path) }
        yield
      ensure
        silence_warnings { Configuration.const_set(:CONFIG_PATH, original) }
      end

      def silence_warnings
        old_verbose = $VERBOSE
        $VERBOSE = nil
        yield
      ensure
        $VERBOSE = old_verbose
      end

      def capture_stderr
        original = $stderr
        $stderr = StringIO.new
        yield
        $stderr.string
      ensure
        $stderr = original
      end
    end
  end
end
