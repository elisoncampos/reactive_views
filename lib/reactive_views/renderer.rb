# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module ReactiveViews
  class Renderer
    class RenderError < StandardError; end

    # Lightweight persistent HTTP client that reuses connections
    class HttpClient
      DEFAULT_HEADERS = {
        "Content-Type" => "application/json",
        "Connection" => "keep-alive",
        "User-Agent" => "ReactiveViews-Ruby"
      }.freeze

      attr_reader :base_url

      def initialize(base_url)
        @base_url = base_url
        @base_uri = URI.parse(base_url)
        @mutex = Mutex.new
        @http = nil
      end

      def post_json(path, body:, headers: {}, timeout: {})
        request = Net::HTTP::Post.new(
          normalized_path(path),
          DEFAULT_HEADERS.merge(headers)
        )
        request.body = JSON.generate(body)

        with_connection(timeout) do |http|
          http.request(request)
        end
      end

      def shutdown
        @mutex.synchronize do
          if @http&.started?
            @http.finish
          end
        rescue IOError
          nil
        ensure
          @http = nil
        end
      end

      private

      def with_connection(timeout)
        attempt = 0
        begin
          attempt += 1
          @mutex.synchronize do
            ensure_connection
            apply_timeouts(timeout)
            return yield(@http)
          end
        rescue IOError, Errno::ECONNRESET, Errno::EPIPE
          shutdown
          retry if attempt < 2
          raise
        end
      end

      def ensure_connection
        return if @http&.started?

        @http = Net::HTTP.new(@base_uri.host, @base_uri.port)
        @http.use_ssl = @base_uri.scheme == "https"
        @http.keep_alive_timeout = 30
        @http.start
      end

      def apply_timeouts(timeout)
        return if timeout.nil? || timeout.empty?

        @http.open_timeout = timeout[:open] if timeout[:open]
        @http.read_timeout = timeout[:read] if timeout[:read]
        @http.write_timeout = timeout[:write] if timeout[:write]
      end

      def normalized_path(path)
        request_path = path.start_with?("/") ? path : "/#{path}"
        base_path = @base_uri.path.to_s
        base_path = "" if base_path == "/" || base_path.empty?
        full_path = "#{base_path}#{request_path}"
        full_path.empty? ? "/" : full_path
      end
    end

    class << self
      def cache
        renderer_cache
      end

      def render(component_name, props = {})
        return "" unless ReactiveViews.config.enabled

        component_path = ComponentResolver.resolve(component_name)

        unless component_path
          error_msg = build_missing_component_error(component_name)
          return handle_error(component_name, props, RenderError.new(error_msg))
        end

        ttl = ReactiveViews.config.ssr_cache_ttl_seconds
        cache_key = generate_cache_key(component_name, props)
        cache_store = renderer_cache

        if ttl && (cached = cache_store.read(cache_key))
          return cached
        end

        result = make_ssr_request(
          component_path,
          props,
          component_name: component_name,
          include_metadata: false
        )
        html = result["html"] || ""

        cache_store.write(cache_key, html, ttl: ttl) if ttl
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

        result = make_ssr_request(
          component_path,
          props,
          component_name: component_path,
          include_metadata: false
        )
        result["html"] || ""
      rescue StandardError => e
        handle_error(component_path, props, e)
      end

      # Render path and return HTML + metadata (used for full-page hydration)
      def render_path_with_metadata(component_path, props = {})
        return { html: "", bundle_key: nil } unless ReactiveViews.config.enabled

        result = make_ssr_request(
          component_path,
          props,
          component_name: component_path,
          include_metadata: true
        )

        {
          html: result["html"] || "",
          bundle_key: result["bundleKey"]
        }
      rescue StandardError => e
        {
          html: handle_error(component_path, props, e),
          bundle_key: nil
        }
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
        make_tree_ssr_request(resolved_tree, tree_spec[:component_name])
      rescue StandardError => e
        { error: e.message }
      end

      def clear_cache
        renderer_cache.clear
      end

      private

      def renderer_cache
        ReactiveViews.config.cache_for(:renderer)
      end

      def build_missing_component_error(component_name)
        search_paths = ReactiveViews.config.component_views_paths + ReactiveViews.config.component_js_paths
        paths_info = search_paths.map do |path|
          if defined?(Rails)
            Rails.root.join(path).to_s
          else
            File.expand_path(path)
          end
        end.join(", ")

        "Component '#{component_name}' not found. Searched in: #{paths_info}"
      end

      def generate_cache_key(component_name, props)
        "#{component_name}:#{props.to_json}"
      end

      def make_ssr_request(component_path, props, component_name:, include_metadata:)
        response = http_client.post_json(
          "/render",
          body: { componentPath: component_path, props: props },
          headers: metadata_headers(
            component_name: component_name,
            component_path: component_path,
            extra: { "X-Reactive-Views-Metadata" => include_metadata ? "true" : "false" }
          ),
          timeout: request_timeouts(:render)
        )

        result = parse_response_body(response)
        raise RenderError, result["error"] if result["error"]

        result
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
        response = http_client.post_json(
          "/batch-render",
          body: { components: valid_requests },
          headers: metadata_headers(batch_size: valid_requests.size),
          timeout: request_timeouts(:batch)
        )

        result = parse_response_body(response)
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

      def make_tree_ssr_request(resolved_tree, root_component_name)
        response = http_client.post_json(
          "/render-tree",
          body: resolved_tree,
          headers: metadata_headers(
            component_name: root_component_name,
            component_path: resolved_tree[:componentPath]
          ),
          timeout: request_timeouts(:tree)
        )

        result = parse_response_body(response)

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

      def parse_response_body(response)
        unless response.is_a?(Net::HTTPSuccess)
          error_message = extract_error_message(response.body)
          raise RenderError, "SSR server returned #{response.code}: #{error_message}"
        end

        JSON.parse(response.body)
      end

      def extract_error_message(body)
        JSON.parse(body)["error"]
      rescue JSON::ParserError
        body
      end

      def metadata_headers(component_name: nil, component_path: nil, batch_size: nil, extra: {})
        headers = {}
        headers["X-ReactiveViews-Component"] = component_name if component_name
        headers["X-ReactiveViews-Component-Path"] = component_path if component_path
        headers["X-ReactiveViews-Batch-Size"] = batch_size.to_s if batch_size
        headers.merge!(extra) if extra
        headers
      end

      def request_timeouts(type)
        config = ReactiveViews.config
        open_timeout = config.ssr_timeout || 2
        read_timeout =
          case type
          when :batch, :tree
            config.batch_timeout || 10
          else
            config.ssr_timeout || 5
          end
        { open: open_timeout, read: read_timeout }
      end

      def http_client
        current_url = ReactiveViews.config.ssr_url
        http_client_mutex.synchronize do
          if !defined?(@http_client) || @http_client.nil? || @http_client.base_url != current_url
            @http_client&.shutdown if defined?(@http_client) && @http_client
            @http_client = HttpClient.new(current_url)
          end

          @http_client
        end
      end

      def http_client_mutex
        @http_client_mutex ||= Mutex.new
      end
    end
  end
end
