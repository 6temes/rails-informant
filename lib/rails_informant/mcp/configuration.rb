module RailsInformant
  module Mcp
    class Configuration
      def initialize(allow_insecure: false)
        @allow_insecure = allow_insecure
        @environments = load_from_env_vars
        @clients = {}

        raise "No environments configured. Set INFORMANT_<ENV>_URL and INFORMANT_<ENV>_TOKEN environment variables." if @environments.empty?
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

        @clients[name] ||= Client.new(url: env[:url], token: env[:token], allow_insecure: @allow_insecure, path_prefix: env[:path_prefix] || "/informant")
      end

      private

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
    end
  end
end
