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

      # Search for component in all paths with all naming variants
      search_paths.each do |base_path|
        next unless Dir.exist?(base_path)

        # Try each naming variant
        name_variants.each do |variant|
          # Try each extension
          EXTENSIONS.each do |ext|
            # Check for direct file match: base_path/Component.tsx
            direct_path = File.join(base_path, "#{variant}#{ext}")
            if (matched = match_file(direct_path))
              log_resolution_success(component_name, matched, variant)
              return matched
            end

            # Check for index file match: base_path/Component/index.tsx
            index_path = File.join(base_path, variant, "index#{ext}")
            if (matched = match_file(index_path))
              log_resolution_success(component_name, matched, variant)
              return matched
            end

            # Check for recursive match: base_path/**/Component.tsx
            # Use glob for recursive search but be careful about performance
            matches = Dir.glob(File.join(base_path, "**", "#{variant}#{ext}"), File::FNM_CASEFOLD)
            if matches.any?
              log_resolution_success(component_name, matches.first, variant)
              return matches.first
            end
          end
        end
      end

      log_resolution_failure(component_name)
      nil
    end

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

    def self.log_resolution_failure(component_name)
      return unless defined?(Rails) && Rails.logger

      Rails.logger.error("[ReactiveViews] Component '#{component_name}' not found in search paths.")
    end

    def self.match_file(path)
      Dir.glob(path, File::FNM_CASEFOLD).find { |matched| File.file?(matched) }
    end
  end
end
