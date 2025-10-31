# frozen_string_literal: true

module ReactiveViews
  class Configuration
    attr_accessor :enabled, :ssr_url, :component_views_paths, :component_js_paths, :ssr_cache_ttl_seconds, :boot_module_path

    def initialize
      @enabled = true
      @ssr_url = ENV.fetch("RV_SSR_URL", "http://localhost:5175")
      @component_views_paths = ["app/views/components"]
      @component_js_paths = ["app/javascript/components"]
      @ssr_cache_ttl_seconds = nil
      @boot_module_path = nil
    end
  end
end

