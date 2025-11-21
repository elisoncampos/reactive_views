# frozen_string_literal: true

require "digest"
require "net/http"
require "json"
require "uri"

module ReactiveViews
  # Props inference client to extract prop keys from TSX component signatures
  class PropsInference
    class InferenceError < StandardError; end

    class << self
      def cache
        inference_cache
      end

      # Infer prop keys from TSX component signature
      #
      # @param tsx_content [String] The TSX/JSX source code
      # @param extension [String] The source extension ('tsx' or 'jsx')
      # @return [Array<String>] Array of prop keys, or empty array on failure
      def infer_props(tsx_content, extension: "tsx")
        return [] unless ReactiveViews.config.props_inference_enabled

        # Generate cache key from content digest
        content_digest = Digest::SHA256.hexdigest(tsx_content)
        ttl = ReactiveViews.config.props_inference_cache_ttl_seconds
        cache_store = inference_cache

        if ttl && (cached = cache_store.read(content_digest))
          return cached
        end

        # Make inference request
        keys = make_inference_request(tsx_content, content_digest, extension)

        # Cache the result
        cache_store.write(content_digest, keys, ttl: ttl) if ttl

        keys
      rescue StandardError => e
        log_error("Props inference failed: #{e.message}")
        [] # Return empty array on failure
      end

      private

      def inference_cache
        ReactiveViews.config.cache_for(:props_inference)
      end

      def make_inference_request(tsx_content, content_digest, extension)
        uri = URI.parse("#{ReactiveViews.config.ssr_url}/infer-props")
        http = Net::HTTP.new(uri.host, uri.port)
        http.read_timeout = ReactiveViews.config.ssr_timeout

        request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
        request.body = JSON.generate({
                                       tsxContent: tsx_content,
                                       contentHash: content_digest,
                                       extension: (extension || "tsx").to_s
                                     })

        response = http.request(request)

        raise InferenceError, "HTTP #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

        result = JSON.parse(response.body)
        result["keys"] || []
      rescue JSON::ParserError => e
        raise InferenceError, "Invalid JSON response: #{e.message}"
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
        raise InferenceError, "Cannot connect to SSR server: #{e.message}"
      rescue Net::ReadTimeout
        raise InferenceError, "Inference request timed out"
      end

      def log_error(message)
        return unless defined?(Rails) && Rails.logger

        Rails.logger.error("[ReactiveViews::PropsInference] #{message}")
      end
    end
  end
end
