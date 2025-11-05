# frozen_string_literal: true

require 'bundler/setup'

# Load the gem first
$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)
require 'reactive_views'

require 'combustion'

Combustion.path = File.expand_path(__dir__)
Combustion.initialize! :action_controller, :action_view do
  config.load_defaults Rails::VERSION::STRING.to_f
  config.eager_load = false
  config.action_controller.perform_caching = false
  config.action_controller.allow_forgery_protection = false
  config.action_dispatch.show_exceptions = :all
  config.consider_all_requests_local = true
end

run Rails.application
