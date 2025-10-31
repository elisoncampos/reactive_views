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

    # Include Vite client tag for HMR in development
    output << vite_client_tag if respond_to?(:vite_client_tag)

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
end

