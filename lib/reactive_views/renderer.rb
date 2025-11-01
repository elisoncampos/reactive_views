# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module ReactiveViews
  class Renderer
    class RenderError < StandardError; end

    # Simple in-memory cache with TTL support
    class Cache
      def initialize
        @store = {}
        @timestamps = {}
      end

      def get(key, ttl_seconds)
        return nil unless @store.key?(key)
        return nil if ttl_seconds && Time.now.to_i - @timestamps[key] > ttl_seconds

        @store[key]
      end

      def set(key, value)
        @store[key] = value
        @timestamps[key] = Time.now.to_i
      end

      def clear
        @store.clear
        @timestamps.clear
      end
    end

    @cache = Cache.new

    class << self
      attr_reader :cache

      def render(component_name, props = {})
        return "" unless ReactiveViews.config.enabled

        # Resolve component path
        component_path = ComponentResolver.resolve(component_name)

        unless component_path
          # Build detailed error message with searched paths
          search_paths = ReactiveViews.config.component_views_paths + ReactiveViews.config.component_js_paths
          paths_info = search_paths.map do |path|
            if defined?(Rails)
              Rails.root.join(path).to_s
            else
              File.expand_path(path)
            end
          end.join(", ")

          error_msg = "Component '#{component_name}' not found. Searched in: #{paths_info}"
          return handle_error(component_name, props, RenderError.new(error_msg))
        end

        # Generate cache key
        cache_key = generate_cache_key(component_name, props)
        ttl = ReactiveViews.config.ssr_cache_ttl_seconds

        # Check cache
        if ttl && (cached = @cache.get(cache_key, ttl))
          return cached
        end

        # Make SSR request
        html = make_ssr_request(component_path, props)

        # Cache the result
        @cache.set(cache_key, html) if ttl

        html
      rescue StandardError => e
        handle_error(component_name, props, e)
      end

      def clear_cache
        @cache.clear
      end

      private

      def generate_cache_key(component_name, props)
        "#{component_name}:#{props.to_json}"
      end

      def make_ssr_request(component_path, props)
        uri = URI.parse("#{ReactiveViews.config.ssr_url}/render")

        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = ReactiveViews.config.ssr_timeout || 2
        http.read_timeout = ReactiveViews.config.ssr_timeout || 5

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        request.body = { componentPath: component_path, props: props }.to_json

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise RenderError, "SSR server returned #{response.code}: #{response.body}"
        end

        result = JSON.parse(response.body)

        if result["error"]
          raise RenderError, "SSR rendering failed: #{result["error"]}"
        end

        result["html"] || ""
      rescue JSON::ParserError => e
        raise RenderError, "Invalid JSON response from SSR server: #{e.message}"
      rescue Errno::ECONNREFUSED
        raise RenderError, "Could not connect to SSR server at #{ReactiveViews.config.ssr_url}"
      rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout
        raise RenderError, "SSR server request timed out"
      end

      def handle_error(component_name, props, error)
        # Log the error
        if defined?(Rails) && Rails.logger
          Rails.logger.error("[ReactiveViews] SSR Error for #{component_name}: #{error.message}")
          Rails.logger.error(error.backtrace.join("\n")) if error.backtrace
        end

        # Return a special marker that TagTransformer can use for error overlay
        "___REACTIVE_VIEWS_ERROR___#{error.message}___"
      end
    end
  end
end
