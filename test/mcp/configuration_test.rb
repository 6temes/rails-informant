require_relative "test_helper"

module RailsInformant
  module Mcp
    class ConfigurationTest < Minitest::Test
      def setup
        @saved_env = ENV.select { |k, _| k.start_with?("INFORMANT_") }
        @saved_env.each_key { |k| ENV.delete(k) }
      end

      def teardown
        # Clear any INFORMANT_ vars set by tests
        ENV.each_key { |k| ENV.delete(k) if k.start_with?("INFORMANT_") }
        # Restore original values
        @saved_env.each { |k, v| ENV[k] = v }
      end

      def test_raises_when_no_environments_configured
        error = assert_raises(RuntimeError) { Configuration.new }
        assert_includes error.message, "No environments configured"
      end

      def test_loads_environment_from_env_vars
        ENV["INFORMANT_PRODUCTION_URL"] = "https://app.example.com"
        ENV["INFORMANT_PRODUCTION_TOKEN"] = "secret"

        config = Configuration.new

        assert_equal [ "production" ], config.environment_names
      end

      def test_loads_multiple_environments_from_env_vars
        ENV["INFORMANT_PRODUCTION_URL"] = "https://app.example.com"
        ENV["INFORMANT_PRODUCTION_TOKEN"] = "secret"
        ENV["INFORMANT_STAGING_URL"] = "https://staging.example.com"
        ENV["INFORMANT_STAGING_TOKEN"] = "staging-secret"

        config = Configuration.new

        assert_includes config.environment_names, "production"
        assert_includes config.environment_names, "staging"
      end

      def test_safe_environments_excludes_tokens
        ENV["INFORMANT_PRODUCTION_URL"] = "https://app.example.com"
        ENV["INFORMANT_PRODUCTION_TOKEN"] = "secret"

        config = Configuration.new

        config.safe_environments.each_value do |env|
          assert_equal [ :url ], env.keys
        end
      end

      def test_safe_environments_includes_urls
        ENV["INFORMANT_PRODUCTION_URL"] = "https://app.example.com"
        ENV["INFORMANT_PRODUCTION_TOKEN"] = "secret"

        config = Configuration.new

        assert_equal "https://app.example.com", config.safe_environments["production"][:url]
      end

      def test_default_environment_returns_first
        ENV["INFORMANT_PRODUCTION_URL"] = "https://app.example.com"
        ENV["INFORMANT_PRODUCTION_TOKEN"] = "secret"

        config = Configuration.new

        assert_equal "production", config.default_environment
      end

      def test_no_public_environments_accessor
        refute Configuration.public_method_defined?(:environments),
          "Configuration should not expose environments publicly"
      end

      def test_client_for_returns_client
        ENV["INFORMANT_PRODUCTION_URL"] = "https://app.example.com"
        ENV["INFORMANT_PRODUCTION_TOKEN"] = "secret"

        config = Configuration.new
        client = config.client_for("production")

        assert_instance_of Client, client
      end

      def test_client_for_passes_allow_insecure
        ENV["INFORMANT_PRODUCTION_URL"] = "http://localhost:3000"
        ENV["INFORMANT_PRODUCTION_TOKEN"] = "secret"

        config = Configuration.new(allow_insecure: true)
        client = config.client_for("production")

        assert_instance_of Client, client
      end

      def test_client_for_unknown_environment_raises
        ENV["INFORMANT_PRODUCTION_URL"] = "https://app.example.com"
        ENV["INFORMANT_PRODUCTION_TOKEN"] = "secret"

        config = Configuration.new
        error = assert_raises(ArgumentError) { config.client_for("unknown") }

        assert_includes error.message, "Unknown environment: unknown"
      end

      def test_path_prefix_from_env_var
        ENV["INFORMANT_PRODUCTION_URL"] = "https://app.example.com"
        ENV["INFORMANT_PRODUCTION_TOKEN"] = "secret"
        ENV["INFORMANT_PRODUCTION_PATH_PREFIX"] = "/errors"

        config = Configuration.new
        envs = config.send(:instance_variable_get, :@environments)

        assert_equal "/errors", envs["production"][:path_prefix]
      end
    end
  end
end
