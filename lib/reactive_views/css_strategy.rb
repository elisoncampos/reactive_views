# frozen_string_literal: true

module ReactiveViews
  # CSS isolation strategies and conflict detection utilities
  # Helps prevent style conflicts between React components and Rails views
  module CssStrategy
    # Common class names that often cause conflicts between React and Rails
    COMMON_CONFLICT_CLASSES = %w[
      btn button card container row col form input label
      header footer nav navbar sidebar menu modal alert
      badge tooltip popover dropdown tab panel
      table list item link icon text title
      primary secondary success danger warning info
      active disabled selected hidden visible
      small medium large
    ].freeze

    # Recommendations for CSS isolation strategies
    STRATEGIES = {
      css_modules: {
        name: "CSS Modules",
        description: "Automatic class name scoping with .module.css files",
        pros: [ "Automatic scoping", "Build-time guarantee", "IDE support" ],
        cons: [ "Requires Vite/bundler setup", "Different syntax from regular CSS" ],
        setup: <<~SETUP
          1. Name your CSS files with .module.css extension
          2. Import styles as objects: import styles from './Component.module.css'
          3. Use styles.className in your JSX
        SETUP
      },
      tailwind_prefix: {
        name: "Tailwind Prefix",
        description: "Configure Tailwind with a prefix for React components",
        pros: [ "Works with existing Tailwind setup", "Easy to configure" ],
        cons: [ "Need to remember prefix", "Doesn't help with custom CSS" ],
        setup: <<~SETUP
          In tailwind.config.js for React components:
          module.exports = {
            prefix: 'rv-',
            content: ['./app/views/components/**/*.tsx'],
          }
        SETUP
      },
      bem_convention: {
        name: "BEM Convention",
        description: "Use Block-Element-Modifier naming with component prefix",
        pros: [ "No tooling required", "Clear naming", "Works everywhere" ],
        cons: [ "Manual discipline required", "Verbose class names" ],
        setup: <<~SETUP
          Use component name as block: ComponentName__element--modifier
          Example: Counter__button--primary
        SETUP
      },
      shadow_dom: {
        name: "Shadow DOM",
        description: "Use Web Components with Shadow DOM for true isolation",
        pros: [ "Complete CSS isolation", "Native browser feature" ],
        cons: [ "Complex setup", "SSR challenges", "Less React-like" ],
        setup: <<~SETUP
          Wrap React components in custom elements with Shadow DOM.
          Note: This requires additional setup and may affect hydration.
        SETUP
      }
    }.freeze

    class << self
      # Check for potential CSS conflicts in component HTML
      # Returns an array of detected conflicts with details
      #
      # @param html [String] The HTML content to analyze
      # @param rails_classes [Array<String>] Known Rails/application CSS classes
      # @return [Array<Hash>] Array of conflict details
      def detect_conflicts(html, rails_classes: [])
        conflicts = []
        all_classes = extract_classes(html)

        # Check against common conflict patterns
        common_conflicts = all_classes & COMMON_CONFLICT_CLASSES
        common_conflicts.each do |class_name|
          conflicts << {
            type: :common_name,
            class_name: class_name,
            message: "Class '#{class_name}' is a common name that may conflict with Rails styles",
            severity: :warning
          }
        end

        # Check against known Rails classes
        rails_conflicts = all_classes & rails_classes
        rails_conflicts.each do |class_name|
          conflicts << {
            type: :rails_conflict,
            class_name: class_name,
            message: "Class '#{class_name}' conflicts with a known Rails application class",
            severity: :error
          }
        end

        conflicts
      end

      # Extract all CSS class names from HTML content
      #
      # @param html [String] The HTML content
      # @return [Array<String>] Unique class names found
      def extract_classes(html)
        return [] if html.blank?

        # Match class attributes and extract individual class names
        classes = []
        html.scan(/class=["']([^"']+)["']/) do |match|
          classes.concat(match[0].split(/\s+/))
        end

        # Also match className for JSX
        html.scan(/className=["']([^"']+)["']/) do |match|
          classes.concat(match[0].split(/\s+/))
        end

        classes.uniq.reject(&:blank?)
      end

      # Generate a scoped class name using the component name as prefix
      #
      # @param component_name [String] The component name (e.g., "Counter")
      # @param class_name [String] The original class name
      # @return [String] Scoped class name (e.g., "rv-counter-button")
      def scoped_class(component_name, class_name)
        prefix = component_name.to_s.underscore.tr("_", "-")
        "rv-#{prefix}-#{class_name}"
      end

      # Check if a CSS file uses CSS Modules syntax
      #
      # @param file_path [String] Path to the CSS file
      # @return [Boolean] True if the file uses CSS Modules
      def uses_css_modules?(file_path)
        return false unless File.exist?(file_path)

        # CSS Modules files typically have .module.css extension
        return true if file_path.end_with?(".module.css", ".module.scss")

        # Also check for :local and :global selectors
        content = File.read(file_path)
        content.include?(":local(") || content.include?(":global(")
      end

      # Get recommended strategy based on project setup
      #
      # @param options [Hash] Project configuration options
      # @return [Symbol] Recommended strategy key
      def recommend_strategy(options = {})
        return :css_modules if options[:vite] || options[:has_bundler]
        return :tailwind_prefix if options[:tailwind]

        :bem_convention
      end

      # Log CSS conflict warnings during development
      def log_conflicts(conflicts, logger: nil)
        return if conflicts.empty?

        logger ||= (defined?(Rails) && Rails.logger)
        return unless logger

        conflicts.each do |conflict|
          case conflict[:severity]
          when :error
            logger.error("[ReactiveViews CSS] #{conflict[:message]}")
          when :warning
            logger.warn("[ReactiveViews CSS] #{conflict[:message]}")
          else
            logger.info("[ReactiveViews CSS] #{conflict[:message]}")
          end
        end
      end
    end
  end
end
