require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "active_job/railtie"

Bundler.require(*Rails.groups)
require "rails_informant"

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.load_defaults 8.1
    config.eager_load = false
    config.active_job.queue_adapter = :test
    config.filter_parameters += [:password, :secret]
  end
end
