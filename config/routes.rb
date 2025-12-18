# frozen_string_literal: true

ReactiveViews::Engine.routes.draw do
  # Proxy full-page bundle requests to the SSR server
  # The client requests: /reactive_views/full-page-bundles/:bundle_key.js
  # We match both with and without the .js extension for flexibility
  get "full-page-bundles/:id", to: "bundles#show", as: :bundle,
      constraints: { id: /[a-f0-9]+/ },
      defaults: { format: "js" }
end
