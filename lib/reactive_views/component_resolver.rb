# frozen_string_literal: true

require "set"

module ReactiveViews
  class ComponentResolver
    EXTENSIONS = %w[.tsx .jsx .ts .js].freeze
    FILE_EVENT = "reactive_views.file_changed"
    COMPONENT_EVENT = "reactive_views.component_changed"

    class << self
      def resolve(component_name, paths = nil)
        setup_notifications!

        # If caller already passed a concrete file path, accept it.
        # Some production/performance specs render by absolute component path.
        if component_name.is_a?(String) && component_name.include?("/")
          expanded = File.expand_path(component_name)
          return expanded if File.file?(expanded)
        end

        search_paths = normalize_paths(paths)
        cache_key = build_cache_key(component_name, search_paths)

        if (cached = cached_path(cache_key))
          return cached
        end

        name_variants = generate_name_variants(component_name)

        search_paths.each do |base_path|
          next unless Dir.exist?(base_path)

          name_variants.each do |variant|
            EXTENSIONS.each do |ext|
              direct_path = File.join(base_path, "#{variant}#{ext}")
              if (matched = match_file(direct_path))
                store_cache(cache_key, matched, component_name)
                log_resolution_success(component_name, matched, variant)
                return matched
              end

              index_path = File.join(base_path, variant, "index#{ext}")
              if (matched = match_file(index_path))
                store_cache(cache_key, matched, component_name)
                log_resolution_success(component_name, matched, variant)
                return matched
              end

              matches = Dir.glob(File.join(base_path, "**", "#{variant}#{ext}"), File::FNM_CASEFOLD)
              if matches.any?
                first_match = matches.first
                store_cache(cache_key, first_match, component_name)
                log_resolution_success(component_name, first_match, variant)
                return first_match
              end
            end
          end
        end

        log_resolution_failure(component_name)
        nil
      end

      def invalidate(component_name: nil, path: nil)
        cache_mutex.synchronize do
          invalidate_by_path(path) if path
          invalidate_by_component(component_name) if component_name
        end
      end

      def clear_cache
        cache_mutex.synchronize do
          cache_store.clear
          path_index.clear
        end
      end

      # Generate all naming convention variants for a component name
      # Supports: PascalCase, snake_case, camelCase, kebab-case
      def generate_name_variants(name)
        variants = []

        variants << name
        variants << to_snake_case(name)
        variants << to_camel_case(name)
        variants << to_kebab_case(name)

        variants.uniq
      end

      # Convert PascalCase to snake_case
      def to_snake_case(name)
        name
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .tr("-", "_")
          .downcase
      end

      # Convert PascalCase to camelCase
      def to_camel_case(name)
        return name if name.empty?

        name[0].downcase + name[1..]
      end

      # Convert PascalCase to kebab-case
      def to_kebab_case(name)
        name
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1-\2')
          .gsub(/([a-z\d])([A-Z])/, '\1-\2')
          .tr("_", "-")
          .downcase
      end

      def log_resolution_success(component_name, path, variant)
        return unless defined?(Rails) && Rails.logger

        variant_info = variant != component_name ? " (as '#{variant}')" : ""
        Rails.logger.debug("[ReactiveViews] Resolved #{component_name}#{variant_info} to #{path}")
      end

      def log_resolution_failure(component_name)
        return unless defined?(Rails) && Rails.logger

        Rails.logger.error("[ReactiveViews] Component '#{component_name}' not found in search paths.")
      end

      def match_file(path)
        Dir.glob(path, File::FNM_CASEFOLD).find { |matched| File.file?(matched) }
      end

      private

      def setup_notifications!
        return unless defined?(ActiveSupport::Notifications)
        return if @notifications_subscribed

        ActiveSupport::Notifications.subscribe(FILE_EVENT) do |_name, _start, _finish, _id, payload|
          invalidate(path: payload[:path]) if payload.is_a?(Hash) && payload[:path]
        end

        ActiveSupport::Notifications.subscribe(COMPONENT_EVENT) do |_name, _start, _finish, _id, payload|
          invalidate(component_name: payload[:component]) if payload.is_a?(Hash) && payload[:component]
        end

        @notifications_subscribed = true
      end

      def normalize_paths(paths)
        paths ||= ReactiveViews.config.component_views_paths + ReactiveViews.config.component_js_paths

        paths.map do |path|
          if path.is_a?(Pathname) || path.start_with?("/")
            path.to_s
          elsif defined?(Rails)
            Rails.root.join(path).to_s
          else
            File.expand_path(path)
          end
        end
      end

      def cached_path(cache_key)
        cache_mutex.synchronize do
          entry = cache_store[cache_key]
          return unless entry

          path = entry[:path]
          return unless File.exist?(path)

          current_mtime = File.mtime(path)
          if entry[:mtime] == current_mtime
            path
          else
            remove_entry(cache_key, path)
            nil
          end
        end
      end

      def store_cache(cache_key, path, component_name)
        normalized_path = File.expand_path(path)
        cache_mutex.synchronize do
          cache_store[cache_key] = {
            path: normalized_path,
            mtime: File.mtime(normalized_path),
            component_name: component_name
          }

          path_index[normalized_path] ||= Set.new
          path_index[normalized_path] << cache_key
        end
      end

      def remove_entry(cache_key, path)
        cache_store.delete(cache_key)
        normalized_path = File.expand_path(path)
        if path_index[normalized_path]
          path_index[normalized_path].delete(cache_key)
          path_index.delete(normalized_path) if path_index[normalized_path].empty?
        end
      end

      def invalidate_by_path(path)
        normalized_path = File.expand_path(path)
        keys = path_index.delete(normalized_path)
        return unless keys

        keys.each { |key| cache_store.delete(key) }
      end

      def invalidate_by_component(component_name)
        return unless component_name

        keys_to_remove = cache_store.each_with_object([]) do |(key, entry), list|
          list << [ key, entry[:path] ] if entry && entry[:component_name] == component_name
        end

        keys_to_remove.each do |key, path|
          remove_entry(key, path)
        end
      end

      def build_cache_key(component_name, search_paths)
        "#{component_name}::#{search_paths.join("||")}"
      end

      def cache_store
        @cache_store ||= {}
      end

      def path_index
        @path_index ||= {}
      end

      def cache_mutex
        @cache_mutex ||= Mutex.new
      end
    end
  end
end
