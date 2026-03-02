require "yaml"

module RailsInformant
  module Mcp
    class Configuration
      attr_reader :allow_insecure, :environments

      def initialize(allow_insecure: false)
        @allow_insecure = allow_insecure
        @environments = load_environments
        @clients = {}
      end

      def default_environment
        environments.keys.first
      end

      def client_for(name)
        env = environments[name]
        raise ArgumentError, "Unknown environment: #{name}. Available: #{environments.keys.join(', ')}" unless env

        @clients[name] ||= Client.new(url: env[:url], token: env[:token], allow_insecure:)
      end

      private

      def load_environments
        envs = load_from_yaml.merge(load_from_env_vars)
        raise "No environments configured. Set INFORMANT_<ENV>_URL and INFORMANT_<ENV>_TOKEN environment variables, or create ~/.config/informant-mcp.yml" if envs.empty?
        envs
      end

      def load_from_env_vars
        ENV.each_with_object({}) do |(key, _), envs|
          next unless (match = key.match(/\AINFORMANT_(.+)_URL\z/))

          env_name = match[1].downcase
          envs[env_name] = {
            url: ENV.fetch(key),
            token: ENV["INFORMANT_#{match[1]}_TOKEN"]
          }
        end
      end

      def load_from_yaml
        path = File.expand_path("~/.config/informant-mcp.yml")
        return {} unless File.exist?(path)

        yaml = YAML.safe_load_file(path)
        return {} unless yaml.is_a?(Hash) && yaml["environments"].is_a?(Hash)

        yaml["environments"].each_with_object({}) do |(name, config), envs|
          next unless config.is_a?(Hash)
          envs[name] = { url: interpolate(config["url"]), token: interpolate(config["token"]) }
        end
      end

      def interpolate(value)
        return value unless value.is_a?(String)
        value.gsub(/\$\{(\w+)\}/) { ENV[$1] || "" }
      end
    end
  end
end
