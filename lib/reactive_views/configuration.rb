# frozen_string_literal: true

module ReactiveViews
  class Configuration
    attr_accessor :enabled, :ssr_url, :component_views_paths, :component_js_paths, :ssr_cache_ttl_seconds, :boot_module_path, :ssr_timeout, :batch_rendering_enabled, :batch_timeout, :tree_rendering_enabled, :max_nesting_depth_warning

    # Alias for easier testing
    alias_method :component_paths, :component_views_paths
    alias_method :component_paths=, :component_views_paths=

    def initialize
      @enabled = true
      @ssr_url = ENV.fetch("RV_SSR_URL", "http://localhost:5175")
      @component_views_paths = ["app/views/components"]
      @component_js_paths = ["app/javascript/components"]
      @ssr_cache_ttl_seconds = nil
      @boot_module_path = nil
      @ssr_timeout = 5
      @batch_rendering_enabled = true
      @batch_timeout = 10
      @tree_rendering_enabled = true
      @max_nesting_depth_warning = 3
    end
  end
end
