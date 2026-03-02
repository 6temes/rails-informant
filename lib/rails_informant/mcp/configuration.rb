require "yaml"

module RailsInformant
  module Mcp
    class Configuration
      CONFIG_PATH = File.expand_path("~/.config/informant-mcp.yml").freeze

      attr_reader :allow_insecure

      def initialize(allow_insecure: false)
        @allow_insecure = allow_insecure
        @environments = load_environments
        @clients = {}
      end

      def default_environment
        environment_names.first
      end

      def environment_names
        @environments.keys
      end

      def safe_environments
        @environments.transform_values { |env| { url: env[:url] } }
      end

      def client_for(name)
        env = @environments[name]
        raise ArgumentError, "Unknown environment: #{name}. Available: #{environment_names.join(', ')}" unless env

        @clients[name] ||= Client.new(url: env[:url], token: env[:token], allow_insecure:, path_prefix: env[:path_prefix] || "/informant")
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
            path_prefix: ENV["INFORMANT_#{match[1]}_PATH_PREFIX"],
            token: ENV["INFORMANT_#{match[1]}_TOKEN"],
            url: ENV.fetch(key)
          }
        end
      end

      def load_from_yaml
        path = CONFIG_PATH
        return {} unless File.exist?(path)

        reject_insecure_permissions(path)

        yaml = YAML.safe_load_file(path)
        return {} unless yaml.is_a?(Hash) && yaml["environments"].is_a?(Hash)

        yaml["environments"].each_with_object({}) do |(name, config), envs|
          next unless config.is_a?(Hash)
          envs[name] = { path_prefix: config["path_prefix"], token: interpolate(config["token"]), url: config["url"] }
        end
      end

      def reject_insecure_permissions(path)
        mode = File.stat(path).mode
        return unless mode & 0o077 != 0

        message = "#{path} has insecure permissions (#{format('%04o', mode & 0o7777)}). Run: chmod 600 #{path}"

        if @allow_insecure
          warn "[RailsInformant] WARNING: #{message}"
        else
          raise "[RailsInformant] #{message} (use --allow-insecure to override)"
        end
      end

      def interpolate(value)
        return value unless value.is_a?(String)
        value.gsub(/\$\{(INFORMANT_\w+)\}/) { ENV[$1] || "" }
      end
    end
  end
end
