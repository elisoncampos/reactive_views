# frozen_string_literal: true

require 'digest'
require 'net/http'
require 'json'
require 'uri'

module ReactiveViews
  # Props inference client to extract prop keys from TSX component signatures
  class PropsInference
    class InferenceError < StandardError; end

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

      # Infer prop keys from TSX component signature
      #
      # @param tsx_content [String] The TSX source code
      # @return [Array<String>] Array of prop keys, or empty array on failure
      def infer_props(tsx_content)
        return [] unless ReactiveViews.config.props_inference_enabled

        # Generate cache key from content digest
        content_digest = Digest::SHA256.hexdigest(tsx_content)
        ttl = ReactiveViews.config.props_inference_cache_ttl_seconds

        # Check cache
        if ttl && (cached = @cache.get(content_digest, ttl))
          return cached
        end

        # Make inference request
        keys = make_inference_request(tsx_content, content_digest)

        # Cache the result
        @cache.set(content_digest, keys) if ttl

        keys
      rescue StandardError => e
        log_error("Props inference failed: #{e.message}")
        [] # Return empty array on failure
      end

      private

      def make_inference_request(tsx_content, content_digest)
        uri = URI.parse("#{ReactiveViews.config.ssr_url}/infer-props")
        http = Net::HTTP.new(uri.host, uri.port)
        http.read_timeout = ReactiveViews.config.ssr_timeout

        request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
        request.body = JSON.generate({
                                       tsxContent: tsx_content,
                                       contentHash: content_digest
                                     })

        response = http.request(request)

        raise InferenceError, "HTTP #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

        result = JSON.parse(response.body)
        result['keys'] || []
      rescue JSON::ParserError => e
        raise InferenceError, "Invalid JSON response: #{e.message}"
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
        raise InferenceError, "Cannot connect to SSR server: #{e.message}"
      rescue Net::ReadTimeout
        raise InferenceError, 'Inference request timed out'
      end

      def log_error(message)
        return unless defined?(Rails) && Rails.logger

        Rails.logger.error("[ReactiveViews::PropsInference] #{message}")
      end
    end
  end
end
