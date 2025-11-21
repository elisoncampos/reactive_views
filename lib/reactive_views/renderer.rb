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

      # Render directly from a component file path (used for full-page TSX.ERB pipeline)
      # @param component_path [String]
      # @param props [Hash]
      # @return [String] SSR HTML
      def render_path(component_path, props = {})
        return "" unless ReactiveViews.config.enabled

        make_ssr_request(component_path, props)
      rescue StandardError => e
        handle_error(component_path, props, e)
      end

      # Batch render multiple components in a single SSR request.
      def batch_render(component_specs)
        return [] if component_specs.empty?

        # If batch rendering is disabled, use individual rendering
        return fallback_to_individual_rendering(component_specs) unless ReactiveViews.config.batch_rendering_enabled

        # Phase 1: Resolve all component paths
        batch_requests = build_batch_requests(component_specs)

        # Phase 2: Attempt batch rendering with fallback
        begin
          make_batch_ssr_request(batch_requests, component_specs)
        rescue StandardError => e
          log_batch_fallback(e)
          fallback_to_individual_rendering(component_specs)
        end
      end

      # Render a component tree with true React composition.
      def tree_render(tree_spec)
        return { error: "Tree rendering disabled" } unless ReactiveViews.config.tree_rendering_enabled

        # Resolve all component paths in the tree
        resolved_tree = resolve_tree_paths(tree_spec)

        # Check if resolution failed
        return { error: resolved_tree[:error] } if resolved_tree[:error]

        # Make tree SSR request
        make_tree_ssr_request(resolved_tree)
      rescue StandardError => e
        { error: e.message }
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
          error_body = response.body
          begin
            error_json = JSON.parse(error_body)
            error_message = error_json["error"] || error_body
          rescue JSON::ParserError
            error_message = error_body
          end
          raise RenderError, "SSR server returned #{response.code}: #{error_message}"
        end

        result = JSON.parse(response.body)

        raise RenderError, result["error"] if result["error"]

        result["html"] || ""
      rescue JSON::ParserError => e
        raise RenderError, "Invalid JSON response from SSR server: #{e.message}"
      rescue Errno::ECONNREFUSED
        raise RenderError, "Could not connect to SSR server at #{ReactiveViews.config.ssr_url}"
      rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout
        raise RenderError, "SSR server request timed out"
      end

      def build_batch_requests(component_specs)
        component_specs.each_with_index.map do |spec, index|
          component_path = ComponentResolver.resolve(spec[:component_name])

          if component_path.nil?
            { index: index, error: "Component '#{spec[:component_name]}' not found" }
          else
            { index: index, componentPath: component_path, props: spec[:props] || {} }
          end
        end
      end

      def make_batch_ssr_request(batch_requests, component_specs)
        errors_by_index, valid_requests, index_mapping = partition_batch_requests(batch_requests)

        batch_results = if valid_requests.empty?
                          []
        else
                          execute_batch_http_request(valid_requests)
        end

        build_results_array(component_specs.size, errors_by_index, batch_results, index_mapping)
      rescue JSON::ParserError => e
        raise RenderError, "Invalid JSON response from SSR server: #{e.message}"
      rescue Errno::ECONNREFUSED
        raise RenderError, "Could not connect to SSR server at #{ReactiveViews.config.ssr_url}"
      rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout
        raise RenderError, "SSR batch request timed out"
      end

      def partition_batch_requests(batch_requests)
        errors_by_index = {}
        valid_requests = []
        index_mapping = []

        batch_requests.each do |req|
          if req[:error]
            errors_by_index[req[:index]] = req[:error]
          else
            index_mapping << req[:index]
            valid_requests << { componentPath: req[:componentPath], props: req[:props] }
          end
        end

        [ errors_by_index, valid_requests, index_mapping ]
      end

      def execute_batch_http_request(valid_requests)
        uri = URI.parse("#{ReactiveViews.config.ssr_url}/batch-render")

        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = ReactiveViews.config.ssr_timeout || 2
        http.read_timeout = ReactiveViews.config.batch_timeout || 10

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        request.body = { components: valid_requests }.to_json

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise RenderError, "SSR server returned #{response.code}: #{response.body}"
        end

        result = JSON.parse(response.body)
        result["results"] || []
      end

      def build_results_array(size, errors_by_index, batch_results, index_mapping)
        results = Array.new(size)

        errors_by_index.each do |index, error|
          results[index] = { error: error }
        end

        batch_results.each_with_index do |batch_result, batch_index|
          original_index = index_mapping[batch_index]
          results[original_index] = if batch_result["html"]
                                      { html: batch_result["html"] }
          elsif batch_result["error"]
                                      { error: batch_result["error"] }
          end
        end

        results
      end

      def fallback_to_individual_rendering(component_specs)
        component_specs.map do |spec|
          html = render(spec[:component_name], spec[:props] || {})

          if html.start_with?("___REACTIVE_VIEWS_ERROR___")
            error_message = html.sub("___REACTIVE_VIEWS_ERROR___", "").sub("___", "")
            { error: error_message }
          else
            { html: html }
          end
        rescue StandardError => e
          { error: e.message }
        end
      end

      def log_batch_fallback(error)
        return unless defined?(Rails) && Rails.logger

        Rails.logger.warn(
          "[ReactiveViews] Batch render failed, falling back to individual requests: #{error.message}"
        )
      end

      def resolve_tree_paths(tree_spec)
        component_path = ComponentResolver.resolve(tree_spec[:component_name])

        unless component_path
          return {
            error: "Component '#{tree_spec[:component_name]}' not found"
          }
        end

        resolved_children = tree_spec[:children].map do |child_spec|
          resolve_tree_paths(child_spec)
        end

        error_child = resolved_children.find { |child| child[:error] }
        return error_child if error_child

        {
          componentPath: component_path,
          props: tree_spec[:props] || {},
          children: resolved_children,
          htmlChildren: tree_spec[:html_children] || ""
        }
      end

      def make_tree_ssr_request(resolved_tree)
        uri = URI.parse("#{ReactiveViews.config.ssr_url}/render-tree")

        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = ReactiveViews.config.ssr_timeout || 2
        http.read_timeout = ReactiveViews.config.batch_timeout || 10

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        request.body = resolved_tree.to_json

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          error_body = response.body
          begin
            error_json = JSON.parse(error_body)
            error_message = error_json["error"] || error_body
          rescue JSON::ParserError
            error_message = error_body
          end
          return { error: "SSR server returned #{response.code}: #{error_message}" }
        end

        result = JSON.parse(response.body)

        if result["error"]
          { error: result["error"] }
        else
          { html: result["html"] || "" }
        end
      rescue JSON::ParserError => e
        { error: "Invalid JSON response from SSR server: #{e.message}" }
      rescue Errno::ECONNREFUSED
        { error: "Could not connect to SSR server at #{ReactiveViews.config.ssr_url}" }
      rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout
        { error: "SSR tree request timed out" }
      end

      def handle_error(component_name, _props, error)
        if defined?(Rails) && Rails.logger
          Rails.logger.error("[ReactiveViews] SSR Error for #{component_name}: #{error.message}")
          Rails.logger.error(error.backtrace.join("\n")) if error.backtrace
        end

        "___REACTIVE_VIEWS_ERROR___#{error.message}___"
      end
    end
  end
end
