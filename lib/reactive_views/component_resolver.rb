# frozen_string_literal: true

module ReactiveViews
  class ComponentResolver
    EXTENSIONS = %w[.tsx .jsx .ts .js].freeze

    def self.resolve(component_name, paths = nil)
      # Search both component_views_paths and component_js_paths
      paths ||= (ReactiveViews.config.component_views_paths + ReactiveViews.config.component_js_paths)

      # Normalize paths to absolute paths
      search_paths = paths.map do |path|
        if path.is_a?(Pathname) || path.start_with?("/")
          path.to_s
        elsif defined?(Rails)
          Rails.root.join(path).to_s
        else
          File.expand_path(path)
        end
      end

      # Generate all naming convention variants
      name_variants = generate_name_variants(component_name)

      # Track searched locations for error reporting
      searched_locations = []

      # Search for component in all paths with all naming variants
      search_paths.each do |base_path|
        unless Dir.exist?(base_path)
          searched_locations << "#{base_path} (directory not found)"
          next
        end

        # Try each naming variant
        name_variants.each do |variant|
          # Try each extension
          EXTENSIONS.each do |ext|
            # Search recursively
            pattern = File.join(base_path, "**", "#{variant}#{ext}")
            matches = Dir.glob(pattern)

            if matches.any?
              log_resolution_success(component_name, matches.first, variant)
              return matches.first
            end

            searched_locations << pattern
          end
        end
      end

      log_resolution_failure(component_name, searched_locations)
      nil
    end

    private

    # Generate all naming convention variants for a component name
    # Supports: PascalCase, snake_case, camelCase, kebab-case
    def self.generate_name_variants(name)
      variants = []

      # 1. Original name (typically PascalCase like "HelloWorld")
      variants << name

      # 2. snake_case (Rails convention: "hello_world")
      variants << to_snake_case(name)

      # 3. camelCase (JavaScript convention: "helloWorld")
      variants << to_camel_case(name)

      # 4. kebab-case (Web component convention: "hello-world")
      variants << to_kebab_case(name)

      # Remove duplicates while preserving order
      variants.uniq
    end

    # Convert PascalCase to snake_case
    # Example: "HelloWorld" -> "hello_world"
    def self.to_snake_case(name)
      name
        .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
        .gsub(/([a-z\d])([A-Z])/, '\1_\2')
        .tr("-", "_")
        .downcase
    end

    # Convert PascalCase to camelCase
    # Example: "HelloWorld" -> "helloWorld"
    def self.to_camel_case(name)
      return name if name.empty?
      name[0].downcase + name[1..]
    end

    # Convert PascalCase to kebab-case
    # Example: "HelloWorld" -> "hello-world"
    def self.to_kebab_case(name)
      name
        .gsub(/([A-Z]+)([A-Z][a-z])/, '\1-\2')
        .gsub(/([a-z\d])([A-Z])/, '\1-\2')
        .tr("_", "-")
        .downcase
    end

    def self.log_resolution_success(component_name, path, variant)
      return unless defined?(Rails) && Rails.logger

      variant_info = variant != component_name ? " (as '#{variant}')" : ""
      Rails.logger.debug("[ReactiveViews] Resolved #{component_name}#{variant_info} to #{path}")
    end

    def self.log_resolution_failure(component_name, searched_locations)
      return unless defined?(Rails) && Rails.logger

      Rails.logger.error("[ReactiveViews] Component '#{component_name}' not found")
      Rails.logger.error("[ReactiveViews] Searched in:")
      searched_locations.each do |location|
        Rails.logger.error("  - #{location}")
      end
    end
  end
end
