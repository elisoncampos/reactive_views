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
  def reactive_views_script_tag
    output = []

    # Advertise SSR URL for the client runtime once
    output << tag.meta(name: "reactive-views-ssr-url", content: ReactiveViews.config.ssr_url)

    # Include Vite client tag for HMR in development
    output << vite_client_tag if respond_to?(:vite_client_tag)

    # Ensure React Refresh preamble is installed BEFORE any TSX runs (development only, NOT in test)
    # NOTE: vite_rails proxies Vite at a base path (e.g., /vite-dev/), so we need the full path
    begin
      if defined?(Rails) && Rails.env.development?
        # Get Vite's base path from vite_rails config (e.g., "/vite-dev/")
        vite_base = begin
          ViteRuby.config.public_output_dir
        rescue StandardError
          "vite-dev"
        end

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
      log_helper_error("react_refresh_preamble", e) if respond_to?(:log_helper_error, true)
    end

    # Include the Vite JavaScript entrypoint
    # The boot script is imported in application.js and bundled by Vite
    output << vite_javascript_tag("application") if respond_to?(:vite_javascript_tag)

    safe_join(output, "\n")
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

  def log_helper_error(method_name, error)
    return unless defined?(Rails) && Rails.logger

    Rails.logger.error("[ReactiveViews] Helper error: #{method_name} failed - #{error.message}")
    Rails.logger.debug(error.backtrace.join("\n")) if Rails.logger.debug?
  end
end
