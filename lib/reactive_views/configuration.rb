# frozen_string_literal: true

module ReactiveViews
  class Configuration
    attr_accessor :enabled,
                  :ssr_url,
                  :component_views_paths,
                  :component_js_paths,
                  :ssr_cache_ttl_seconds,
                  :boot_module_path,
                  :ssr_timeout,
                  :batch_rendering_enabled,
                  :batch_timeout,
                  :tree_rendering_enabled,
                  :max_nesting_depth_warning,
                  :props_inference_enabled,
                  :props_inference_cache_ttl_seconds,
                  :full_page_enabled,
                  :cache_namespace,
                  # Asset host for CDN deployments
                  :asset_host

    attr_reader :cache_store

    # Alias for easier testing
    alias component_paths component_views_paths
    alias component_paths= component_views_paths=

    def initialize
      @enabled = true
      # RV_SSR_URL is the primary env var, REACTIVE_VIEWS_SSR_URL is kept for backwards compatibility
      @ssr_url = ENV.fetch("RV_SSR_URL") { ENV.fetch("REACTIVE_VIEWS_SSR_URL", "http://localhost:5175") }
      @component_views_paths = [ "app/views/components" ]
      @component_js_paths = [ "app/javascript/components" ]
      @ssr_cache_ttl_seconds = nil
      @boot_module_path = nil
      @ssr_timeout = ENV.fetch("RV_SSR_TIMEOUT") { ENV.fetch("REACTIVE_VIEWS_SSR_TIMEOUT", 5) }.to_i
      @batch_rendering_enabled = true
      @batch_timeout = 10
      @tree_rendering_enabled = true
      @max_nesting_depth_warning = 3
      @props_inference_enabled = true
      @props_inference_cache_ttl_seconds = 300
      @full_page_enabled = true
      @cache_namespace = "reactive_views"
      self.cache_store = :memory

      # Asset host for CDN deployments
      @asset_host = ENV["ASSET_HOST"]
    end

    def cache_store=(store)
      @cache_store = CacheStore.build(store)
    end

    def cache_for(scope)
      scope_name = scope.to_s
      cache_store.namespaced("#{cache_namespace}:#{scope_name}")
    end

    # Returns true if SSR is available and enabled
    def ssr_enabled?
      enabled && ssr_url.present?
    end

    # Returns true if the application is in production mode
    def production?
      defined?(Rails) && Rails.env.production?
    end
  end
end
