# frozen_string_literal: true

require "monitor"

begin
  require "active_support/cache"
rescue LoadError
  # ActiveSupport is optional – only required when users opt into AS-based stores.
end

module ReactiveViews
  module CacheStore
    class << self
      def build(store)
        case store
        when nil
          MemoryStore.new
        when Base
          store
        when Symbol
          build_from_symbol(store)
        when Array
          symbol, *args = store
          build_from_symbol(symbol, *args)
        else
          wrap_custom_store(store)
        end
      end

      private

      def build_from_symbol(symbol, options = nil)
        case symbol
        when :memory
          MemoryStore.new
        when :redis, :redis_cache_store, :solid_cache, :solid_cache_store, :memory_store
          ensure_active_support_store!(symbol)
          as_symbol = normalize_active_support_symbol(symbol)
          store = ActiveSupport::Cache.lookup_store(as_symbol, options || {})
          ActiveSupportStore.new(store)
        else
          raise ArgumentError, "Unsupported cache store: #{symbol.inspect}"
        end
      end

      def wrap_custom_store(store)
        if defined?(ActiveSupport::Cache::Store) && store.is_a?(ActiveSupport::Cache::Store)
          ActiveSupportStore.new(store)
        elsif store.respond_to?(:read) && store.respond_to?(:write)
          GenericStore.new(store)
        else
          raise ArgumentError, "Cache store must respond to #read and #write"
        end
      end

      def ensure_active_support_store!(symbol)
        return if defined?(ActiveSupport::Cache)

        raise ArgumentError,
              "ActiveSupport::Cache is required for #{symbol} cache_store. Please add activesupport and require it before configuring ReactiveViews."
      end

      def normalize_active_support_symbol(symbol)
        case symbol
        when :redis
          :redis_cache_store
        when :solid_cache
          :solid_cache_store
        when :memory
          :memory_store
        else
          symbol
        end
      end
    end

    class Base
      def namespaced(prefix)
        namespaces_mutex.synchronize do
          @namespaces ||= {}
          @namespaces[prefix] ||= NamespacedStore.new(self, prefix)
        end
      end

      def read(_key)
        raise NotImplementedError
      end

      def write(_key, _value, ttl: nil)
        raise NotImplementedError
      end

      def delete(_key); end

      def clear; end

      def delete_matched(_pattern)
        raise NotImplementedError
      end

      private

      def namespaces_mutex
        @namespaces_mutex ||= Mutex.new
      end
    end

    class NamespacedStore < Base
      def initialize(store, prefix)
        @store = store
        @prefix = prefix
      end

      def read(key)
        @store.read(namespaced(key))
      end

      def write(key, value, ttl: nil)
        @store.write(namespaced(key), value, ttl: ttl)
      end

      def delete(key)
        @store.delete(namespaced(key))
      end

      def clear
        pattern = "#{@prefix}:*"
        if @store.respond_to?(:delete_matched)
          @store.delete_matched(pattern)
        else
          @store.clear
        end
      end

      def delete_matched(suffix_pattern)
        full_pattern = "#{@prefix}:#{suffix_pattern}"
        if @store.respond_to?(:delete_matched)
          @store.delete_matched(full_pattern)
        else
          @store.clear
        end
      end

      private

      def namespaced(key)
        "#{@prefix}:#{key}"
      end
    end

    class MemoryStore < Base
      Entry = Struct.new(:value, :expires_at)

      def initialize
        @store = {}
        @monitor = Monitor.new
      end

      def read(key)
        @monitor.synchronize do
          entry = @store[key]
          return nil unless entry

          if entry.expires_at && entry.expires_at <= Time.now
            @store.delete(key)
            return nil
          end

          entry.value
        end
      end

      def write(key, value, ttl: nil)
        expires_at = ttl ? Time.now + ttl : nil
        @monitor.synchronize do
          @store[key] = Entry.new(value, expires_at)
        end
      end

      def delete(key)
        @monitor.synchronize { @store.delete(key) }
      end

      def clear
        @monitor.synchronize { @store.clear }
      end

      def delete_matched(pattern)
        regex = glob_to_regex(pattern)
        @monitor.synchronize do
          @store.keys.each do |key|
            @store.delete(key) if regex.match?(key)
          end
        end
      end

      private

      def glob_to_regex(pattern)
        Regexp.new("^" + pattern.gsub(".", "\\.").gsub("*", ".*") + "$")
      end
    end

    class ActiveSupportStore < Base
      def initialize(store)
        @store = store
      end

      def read(key)
        @store.read(key)
      end

      def write(key, value, ttl: nil)
        options = ttl ? { expires_in: ttl } : {}
        @store.write(key, value, **options)
      end

      def delete(key)
        @store.delete(key)
      end

      def clear
        @store.clear
      end

      def delete_matched(pattern)
        if @store.respond_to?(:delete_matched)
          @store.delete_matched(pattern)
        else
          @store.clear
        end
      end
    end

    class GenericStore < Base
      def initialize(store)
        @store = store
      end

      def read(key)
        @store.read(key)
      end

      def write(key, value, ttl: nil)
        if @store.method(:write).arity.zero?
          @store.write(key, value)
        else
          @store.write(key, value, ttl: ttl)
        end
      end

      def delete(key)
        @store.delete(key) if @store.respond_to?(:delete)
      end

      def clear
        @store.clear if @store.respond_to?(:clear)
      end

      def delete_matched(pattern)
        if @store.respond_to?(:delete_matched)
          @store.delete_matched(pattern)
        elsif @store.respond_to?(:clear)
          @store.clear
        end
      end
    end
  end
end
