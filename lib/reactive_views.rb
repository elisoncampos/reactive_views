# frozen_string_literal: true

require_relative "reactive_views/version"
require_relative "reactive_views/configuration"
require_relative "reactive_views/component_resolver"
require_relative "reactive_views/renderer"
require_relative "reactive_views/error_overlay"
require_relative "reactive_views/tag_transformer"
require_relative "reactive_views/helpers"
require_relative "reactive_views/props_inference"

if defined?(Rails)
  require_relative "reactive_views/railtie"
end

module ReactiveViews
  class Error < StandardError; end

  class << self
    attr_accessor :config

    def configure
      self.config ||= Configuration.new
      yield(config) if block_given?
    end
  end

  # Initialize with default configuration
  configure
end
