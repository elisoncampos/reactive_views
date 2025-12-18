# frozen_string_literal: true

require "net/http"

module ReactiveViews
  class BundlesController < ActionController::Base
    # Proxy full-page bundle requests to the local SSR server.
    # This allows the client to fetch bundles via same-origin requests,
    # even when the SSR server is only listening on localhost.
    def show
      bundle_key = params[:id]

      # Validate bundle key format (should be a SHA1 hash)
      unless bundle_key.match?(/\A[a-f0-9]{40}\z/)
        render plain: "Invalid bundle key", status: :bad_request
        return
      end

      # Ensure SSR process is running
      SsrProcess.ensure_running

      # Proxy the request to the SSR server
      ssr_url = ReactiveViews.config.ssr_url
      uri = URI.parse("#{ssr_url}/full-page-bundles/#{bundle_key}.js")

      begin
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 5
        http.read_timeout = 10

        response = http.get(uri.path)

        if response.is_a?(Net::HTTPSuccess)
          # Stream the JavaScript bundle back to the client
          render body: response.body,
                 content_type: "application/javascript",
                 status: :ok
        else
          render plain: "Bundle not found", status: :not_found
        end
      rescue Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
        Rails.logger.error("[ReactiveViews] Bundle proxy error: #{e.message}")
        render plain: "SSR server unavailable", status: :service_unavailable
      end
    end
  end
end

