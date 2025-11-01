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
    vite_available = defined?(ViteRails)

    unless vite_available
      if defined?(Rails) && Rails.env.development?
        Rails.logger.warn("[ReactiveViews] vite_rails gem not detected. ReactiveViews requires vite_rails to function properly.")
        return content_tag(:div, "⚠️ ReactiveViews requires vite_rails gem",
                          style: "background: #fee; border: 2px solid #c00; padding: 1rem; margin: 1rem;").html_safe
      end
      return "".html_safe
    end

    # Include Vite client tag for HMR in development
    begin
      if respond_to?(:vite_client_tag)
        output << vite_client_tag
      end
    rescue NoMethodError => e
      log_helper_error("vite_client_tag", e)
    end

    # Include the Vite JavaScript entrypoint
    # The boot script is imported in application.js and bundled by Vite
    begin
      if respond_to?(:vite_javascript_tag)
        output << vite_javascript_tag("application")
      end
    rescue NoMethodError => e
      log_helper_error("vite_javascript_tag", e)
      if defined?(Rails) && Rails.env.development?
        return content_tag(:div, "⚠️ ReactiveViews Error: vite_javascript_tag failed. Ensure vite_rails is properly installed.",
                          style: "background: #fee; border: 2px solid #c00; padding: 1rem; margin: 1rem;").html_safe
      end
    end

    output.compact.empty? ? "".html_safe : safe_join(output, "\n")
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
