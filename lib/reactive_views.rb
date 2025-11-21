# frozen_string_literal: true

require_relative "reactive_views/version"
require_relative "reactive_views/cache_store"
require_relative "reactive_views/configuration"
require_relative "reactive_views/component_resolver"
require_relative "reactive_views/renderer"
require_relative "reactive_views/full_page_renderer"
require_relative "reactive_views/error_overlay"
require_relative "reactive_views/tag_transformer"
require_relative "reactive_views/helpers"
require_relative "reactive_views/props_inference"
require_relative "reactive_views/temp_file_manager"
require_relative "reactive_views/props_builder"
require_relative "reactive_views/template_handler"
require_relative "reactive_views/resolver"

require_relative "reactive_views/railtie" if defined?(Rails)

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
