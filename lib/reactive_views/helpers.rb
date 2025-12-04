# frozen_string_literal: true

module ReactiveViewsHelper
  # Single helper that includes everything needed for ReactiveViews to work.
  # This abstracts away Vite implementation details for a better developer experience.
  #
  # Usage in your application layout:
  #   <%= reactive_views_script_tag %>
  #
  # This helper automatically includes:
  # - Vite client (for HMR in development)
  # - Vite JavaScript entrypoint (which imports the boot script)
  # - SSR URL meta tag for client runtime
  #
  # In production, it serves precompiled assets from the Vite manifest.
  def reactive_views_script_tag
    output = []

    # Advertise SSR URL for the client runtime
    # In production, this should point to the SSR service
    ssr_url = resolve_ssr_url
    output << tag.meta(name: "reactive-views-ssr-url", content: ssr_url)

    # Production mode: serve precompiled assets
    if production_mode?
      output << production_script_tags
    else
      # Development/test mode: use Vite dev server
      output << development_script_tags
    end

    safe_join(output.flatten.compact, "\n")
  end

  # Returns the asset host URL for CDN deployments
  # Can be configured via:
  # - ReactiveViews.config.asset_host
  # - ENV['ASSET_HOST']
  # - Rails.application.config.asset_host
  def reactive_views_asset_host
    ReactiveViews.config.asset_host ||
      ENV["ASSET_HOST"] ||
      (defined?(Rails) && Rails.application.config.asset_host)
  end

  # @deprecated Use {#reactive_views_script_tag} instead.
  # This helper is maintained for backward compatibility but will be removed in future versions.
  def reactive_views_boot
    warn "[DEPRECATION] `reactive_views_boot` is deprecated. Please use `reactive_views_script_tag` instead."
    javascript_include_tag(
      ReactiveViews.config.boot_module_path || "/vite/assets/reactive_views_boot.js",
      defer: true,
      crossorigin: "anonymous"
    )
  end

  private

  def production_mode?
    return false unless defined?(Rails)

    Rails.env.production?
  end

  def resolve_ssr_url
    # Allow configuration override, then environment variable, then default
    ReactiveViews.config.ssr_url ||
      ENV.fetch("REACTIVE_VIEWS_SSR_URL", "http://localhost:5175")
  end

  def production_script_tags
    output = []

    begin
      # In production, vite_rails handles manifest resolution
      # The vite_javascript_tag will automatically use the manifest
      if respond_to?(:vite_javascript_tag)
        output << vite_javascript_tag("application")
      else
        # Fallback: manually resolve from manifest
        output << manual_production_script_tag
      end
    rescue StandardError => e
      log_helper_error("production_script_tags", e)
      # Return a helpful error comment in development-like environments
      output << "<!-- ReactiveViews: Error loading production assets: #{e.message} -->".html_safe
    end

    output
  end

  def development_script_tags
    output = []

    # Include Vite client tag for HMR in development
    output << vite_client_tag if respond_to?(:vite_client_tag)

    # Ensure React Refresh preamble is installed BEFORE any TSX runs (development only, NOT in test)
    # NOTE: vite_rails proxies Vite at a base path (e.g., /vite-dev/), so we need the full path
    begin
      if defined?(Rails) && Rails.env.development?
        vite_base = resolve_vite_base_path

        preamble = <<~JS
          import RefreshRuntime from "/#{vite_base}/@react-refresh";
          RefreshRuntime.injectIntoGlobalHook(window);
          window.$RefreshReg$ = () => {};
          window.$RefreshSig$ = () => (type) => type;
          window.__vite_plugin_react_preamble_installed__ = true;
        JS
        output << content_tag(:script, preamble.html_safe, type: "module")
      end
    rescue StandardError => e
      log_helper_error("react_refresh_preamble", e)
    end

    # Include the Vite JavaScript entrypoint
    # The boot script is imported in application.js and bundled by Vite
    output << vite_javascript_tag("application") if respond_to?(:vite_javascript_tag)

    output
  end

  def resolve_vite_base_path
    ViteRuby.config.public_output_dir
  rescue StandardError
    "vite-dev"
  end

  def manual_production_script_tag
    # Fallback for when vite_rails helpers are not available
    # This reads the manifest directly and generates the appropriate script tag
    manifest_path = Rails.root.join("public", "vite", ".vite", "manifest.json")

    unless File.exist?(manifest_path)
      # Try alternate manifest location
      manifest_path = Rails.root.join("public", "vite", "manifest.json")
    end

    unless File.exist?(manifest_path)
      raise ReactiveViews::AssetManifestNotFoundError,
            "Vite manifest not found. Run 'bin/vite build' to precompile assets."
    end

    manifest = JSON.parse(File.read(manifest_path))
    entry = manifest["app/javascript/entrypoints/application.js"] || manifest["application.js"]

    unless entry
      raise ReactiveViews::AssetEntryNotFoundError,
            "Application entry not found in Vite manifest. Check your vite.config.ts entry points."
    end

    asset_path = build_asset_path(entry["file"])

    # Include CSS if present
    css_tags = (entry["css"] || []).map do |css_file|
      tag.link(rel: "stylesheet", href: build_asset_path(css_file))
    end

    script_tag = tag.script(src: asset_path, type: "module", crossorigin: "anonymous")

    safe_join([ css_tags, script_tag ].flatten, "\n")
  end

  def build_asset_path(file)
    host = reactive_views_asset_host
    path = "/vite/#{file}"

    host ? "#{host.chomp('/')}#{path}" : path
  end

  def log_helper_error(method_name, error)
    return unless defined?(Rails) && Rails.logger

    Rails.logger.error("[ReactiveViews] Helper error: #{method_name} failed - #{error.message}")
    Rails.logger.debug(error.backtrace.join("\n")) if Rails.logger.debug?
  end
end
