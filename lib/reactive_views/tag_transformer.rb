# frozen_string_literal: true

require "nokogiri"
require "securerandom"
require "json"
require "strscan"

module ReactiveViews
  class TagTransformer
    # Transform HTML containing React component tags into SSR'd islands
    # Example: <PostList posts='[...]' /> becomes a hydration island
    def self.transform(html)
      return html unless ReactiveViews.config.enabled
      return html if html.nil? || html.empty?
      return html unless contains_pascal_case_tag?(html)

      # Extract original component names before Nokogiri lowercases them
      component_name_map = extract_component_names(html)

      return html if component_name_map.empty?

      # Convert self-closing tags to explicitly closed tags for HTML5 parser
      # This prevents HTML5 from treating <Component /> as an opening tag
      processed_html = html.gsub(%r{<([A-Z][a-zA-Z0-9]*)\s*([^>]*?)/\s*>}, '<\1 \2></\1>')

      doc = Nokogiri::HTML5.fragment(processed_html)

      # Build component tree to detect nesting
      tree_result = build_component_tree(doc, component_name_map)

      return html if tree_result[:nodes].empty?

      # Initialize script collection context
      context = { scripts: [] }

      # Adaptive rendering strategy: choose between tree and batch rendering
      if tree_result[:has_nesting] && ReactiveViews.config.tree_rendering_enabled
        # Use tree rendering for nested components
        tree_transform_components(tree_result[:nodes], component_name_map, context)
      elsif ReactiveViews.config.batch_rendering_enabled
        # Use batch rendering for flat layouts
        component_nodes = find_component_nodes(doc, component_name_map)
        batch_transform_components(component_nodes, component_name_map, context)
      else
        # Fall back to individual rendering
        component_nodes = find_component_nodes(doc, component_name_map)
        component_nodes.each do |node|
          transform_component_node(node, component_name_map, context)
        end
      end

      # Convert back to HTML and inject collected scripts
      html_output = doc.to_html
      inject_scripts(html_output, context[:scripts])
    rescue StandardError => e
      # Log error but return original HTML to avoid breaking the page
      if defined?(Rails) && Rails.logger
        Rails.logger.error("[ReactiveViews] TagTransformer error: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
      end
      html
    end

    private_class_method def self.inject_scripts(html, scripts)
      return html if scripts.empty?

      scripts_html = scripts.join("\n")

      # Try to inject before </body>
      if html.include?("</body>")
        html.sub("</body>", "#{scripts_html}\n</body>")
      else
        # No body tag, append at end
        "#{html}\n#{scripts_html}"
      end
    end

    private_class_method def self.extract_component_names(html)
      component_map = {}
      scanner = StringScanner.new(html)

      while scanner.scan_until(/<([A-Z][a-zA-Z0-9]*)([^>]*)\/?>/m)
        component_name = scanner[1]
        attrs_segment = scanner[2] || ""
        lowercase_name = component_name.downcase

        entry = (component_map[lowercase_name] ||= { name: component_name, attrs: {} })

        attrs_scanner = StringScanner.new(attrs_segment)
        while attrs_scanner.scan_until(/([a-zA-Z_][a-zA-Z0-9_-]*)\s*=/)
          attr_name = attrs_scanner[1]
          entry[:attrs][attr_name.downcase] = attr_name
        end
      end

      component_map
    end

    # Transform components using tree rendering (for nested components)
    # This method sends the entire component tree to the SSR server
    # which renders it as a single React tree, enabling true composition
    private_class_method def self.tree_transform_components(tree_nodes, _component_name_map, context)
      # Check nesting depth and warn if too deep
      max_depth = calculate_tree_depth(tree_nodes)
      if (max_depth > ReactiveViews.config.max_nesting_depth_warning) && defined?(Rails) && Rails.logger
        Rails.logger.warn(
          "[ReactiveViews] Component nesting depth (#{max_depth}) exceeds recommended maximum " \
          "(#{ReactiveViews.config.max_nesting_depth_warning}). Consider flattening the component tree for better performance."
        )
      end

      # Render each root tree node
      tree_nodes.each do |tree_node|
        render_tree_node(tree_node, context)
      end
    end

    # Calculate the maximum depth of a component tree
    private_class_method def self.calculate_tree_depth(tree_nodes)
      return 0 if tree_nodes.empty?

      tree_nodes.map { |node| calculate_node_depth(node) }.max
    end

    # Calculate depth of a single tree node
    private_class_method def self.calculate_node_depth(tree_node)
      return 1 if tree_node[:children].empty?

      1 + calculate_tree_depth(tree_node[:children])
    end

    # Render a single tree node (recursively)
    private_class_method def self.render_tree_node(tree_node, context)
      uuid = SecureRandom.uuid

      # Build tree spec for SSR server
      tree_spec = build_tree_spec(tree_node)

      # Render via tree endpoint
      result = ReactiveViews::Renderer.tree_render(tree_spec)

      # Handle result
      if result[:error]
        handle_ssr_error(
          tree_node[:node],
          tree_node[:component_name],
          tree_node[:props],
          "___REACTIVE_VIEWS_ERROR___#{result[:error]}___"
        )
      elsif result[:html]
        create_island(
          tree_node[:node],
          tree_node[:component_name],
          uuid,
          tree_node[:props],
          result[:html],
          context
        )
      end
    end

    # Build a spec for the SSR server to render a component tree
    private_class_method def self.build_tree_spec(tree_node)
      {
        component_name: tree_node[:component_name],
        props: tree_node[:props],
        children: tree_node[:children].map { |child| build_tree_spec(child) },
        html_children: tree_node[:html_children].map(&:to_html).join
      }
    end

    # Batch transform all component nodes in one SSR request
    #
    # This method uses a two-phase approach:
    # 1. Collect all component specs and generate UUIDs
    # 2. Batch render via single HTTP request
    # 3. Apply results to nodes in order
    #
    # Performance: N components = 1 HTTP request (vs N requests individually)
    private_class_method def self.batch_transform_components(component_nodes, component_name_map, context)
      # Phase 1: Collect component specs and store original node positions
      component_specs = []
      node_data = []

      # Convert NodeSet to array to avoid live collection issues
      nodes_array = component_nodes.to_a

      nodes_array.each do |node|
        lowercase_name = node.name.downcase
        component_info = component_name_map[lowercase_name]

        # Handle both old format (string) and new format (hash with :name and :attrs)
        component_name = if component_info.is_a?(Hash) && component_info[:name]
                           component_info[:name]
        elsif component_info.is_a?(String)
                           component_info
        else
                           to_pascal_case(node.name)
        end

        uuid = SecureRandom.uuid
        props = extract_props(node, component_info.is_a?(Hash) ? component_info : nil)

        component_specs << {
          uuid: uuid,
          component_name: component_name,
          props: props
        }

        # Store node data
        node_data << {
          node: node,
          component_name: component_name,
          uuid: uuid,
          props: props
        }
      end

      # Phase 2: Batch render all components in one request
      results = ReactiveViews::Renderer.batch_render(component_specs)

      # Phase 3: Apply results to ALL nodes
      # Process in normal order since we have a static array
      results.each_with_index do |result, index|
        data = node_data[index]

        if result[:error]
          handle_ssr_error(
            data[:node],
            data[:component_name],
            data[:props],
            "___REACTIVE_VIEWS_ERROR___#{result[:error]}___"
          )
        elsif result[:html]
          create_island(
            data[:node],
            data[:component_name],
            data[:uuid],
            data[:props],
            result[:html],
            context
          )
        end
      end
    end

    private_class_method def self.find_component_nodes(doc, component_name_map)
      return Nokogiri::XML::NodeSet.new(doc) if component_name_map.nil? || component_name_map.empty?

      doc.css("*").select do |node|
        next false if node.name.downcase.start_with?("reactive_views_")

        component_name_map.key?(node.name.downcase)
      end
    end

    # Build a tree structure representing nested components
    # Returns: { nodes: [tree_node, ...], has_nesting: bool }
    # tree_node: { node:, component_name:, props:, children: [...], html_children: [...] }
    private_class_method def self.build_component_tree(doc, component_name_map)
      all_component_nodes = find_component_nodes(doc, component_name_map)
      return { nodes: [], has_nesting: false } if all_component_nodes.empty?

      # Find root components (not nested inside other components)
      component_node_set = Set.new(all_component_nodes)
      root_nodes = []
      has_nesting = false

      all_component_nodes.each do |node|
        is_root = true
        parent = node.parent

        # Walk up the tree to see if this node is inside another component
        while parent && parent != doc
          if component_node_set.include?(parent)
            is_root = false
            has_nesting = true
            break
          end
          parent = parent.parent
        end

        root_nodes << node if is_root
      end

      # Build tree for each root node
      tree_nodes = root_nodes.map do |root|
        build_tree_node(root, component_name_map, component_node_set)
      end

      { nodes: tree_nodes, has_nesting: has_nesting }
    end

    # Recursively build a tree node for a component
    private_class_method def self.build_tree_node(node, component_name_map, component_node_set)
      lowercase_name = node.name.downcase
      component_info = component_name_map[lowercase_name]

      # Handle both old format (string) and new format (hash with :name and :attrs)
      component_name = if component_info.is_a?(Hash) && component_info[:name]
                         component_info[:name]
      elsif component_info.is_a?(String)
                         component_info
      else
                         to_pascal_case(node.name)
      end

      props = extract_props(node, component_info.is_a?(Hash) ? component_info : nil)

      # Find child components and separate them from HTML children
      component_children = []
      html_children = []

      node.children.each do |child|
        if component_node_set.include?(child)
          # It's a component - recursively build its tree
          component_children << build_tree_node(child, component_name_map, component_node_set)
        else
          # It's HTML content - preserve it
          html_children << child unless child.text? && child.content.strip.empty?
        end
      end

      {
        node: node,
        component_name: component_name,
        props: props,
        children: component_children,
        html_children: html_children
      }
    end

    private_class_method def self.transform_component_node(node, component_name_map, context)
      # Get the original PascalCase name from our map
      lowercase_name = node.name.downcase
      component_info = component_name_map[lowercase_name]

      # Handle both old format (string) and new format (hash with :name and :attrs)
      component_name = if component_info.is_a?(Hash) && component_info[:name]
                         component_info[:name]
      elsif component_info.is_a?(String)
                         component_info
      else
                         to_pascal_case(node.name)
      end

      uuid = SecureRandom.uuid

      # Extract props from attributes
      props = extract_props(node, component_info.is_a?(Hash) ? component_info : nil)

      # Render component via SSR
      ssr_html = ReactiveViews::Renderer.render(component_name, props)

      # Check for error marker
      if ssr_html.start_with?("___REACTIVE_VIEWS_ERROR___")
        handle_ssr_error(node, component_name, props, ssr_html)
        return
      end

      # Create the island container
      create_island(node, component_name, uuid, props, ssr_html, context)
    end

    private_class_method def self.extract_props(node, component_info = nil)
      props = {}

      node.attributes.each do |name, attr|
        value = attr.value

        # Restore original attribute name case if we have component_info
        original_name = if component_info && component_info[:attrs] && component_info[:attrs][name]
                          component_info[:attrs][name]
        else
                          name
        end

        props[original_name] = parse_prop_value(value)
      end

      props
    end

    # Parse a prop value, handling JSX-style expressions and JSON
    private_class_method def self.parse_prop_value(value)
      return value if value.nil?

      # Handle direct JSON values (arrays, objects) FIRST
      # This must come before JSX expression check to avoid stripping outer braces from JSON
      if value.start_with?("[") || (value.start_with?("{") && value.include?(":"))
        begin
          return JSON.parse(value)
        rescue JSON::ParserError
          # Fall through to other checks if JSON parsing fails
        end
      end

      # Handle JSX-style expressions like {10}, {true}, {false}, {1.5}, {"string"}
      # These come from ERB templates where users write <Component prop={value} />
      # Note: JSON objects/arrays are handled above, so this only catches simple expressions
      if value =~ /^\{(.+)\}$/
        inner = ::Regexp.last_match(1).strip

        # Try to parse the inner value
        return true if inner == "true"
        return false if inner == "false"
        return nil if inner == "null" || inner == "nil"

        # Try as integer
        return inner.to_i if inner =~ /^-?\d+$/

        # Try as float
        return inner.to_f if inner =~ /^-?\d+\.\d+$/

        # Try as JSON (for objects/arrays/strings inside JSX expressions)
        begin
          return JSON.parse(inner)
        rescue JSON::ParserError
          # If it looks like a quoted string, try parsing the whole thing
          if inner.start_with?('"') || inner.start_with?("'")
            begin
              return JSON.parse(inner.gsub("'", '"'))
            rescue JSON::ParserError
              return inner
            end
          end
          return inner
        end
      end

      # Handle boolean strings
      return true if value == "true"
      return false if value == "false"

      # Handle numeric strings
      return value.to_i if value =~ /^-?\d+$/
      return value.to_f if value =~ /^-?\d+\.\d+$/

      # Default: return as string
      value
    end

    private_class_method def self.create_island(node, component_name, uuid, props, ssr_html, context = nil)
      # Create container div
      container = Nokogiri::XML::Node.new("div", node.document)
      container["data-island-uuid"] = uuid
      container["data-component"] = component_name

      # Add SSR'd HTML as inner content
      container.inner_html = ssr_html

      # Only create props script tag if there are actual props
      if props && !props.empty?
        script = Nokogiri::XML::Node.new("script", node.document)
        script["type"] = "application/json"
        script["data-island-uuid"] = uuid
        script.content = props.to_json

        # Collect script for later injection if context is provided
        if context
          context[:scripts] << script.to_html
        else
          # Fallback: add inline (for backward compatibility)
          node.add_next_sibling(script)
        end
      end

      # Replace the original node
      node.replace(container)
    end

    private_class_method def self.handle_ssr_error(node, component_name, props, error_html)
      # Extract error from marker
      error_message = error_html.sub("___REACTIVE_VIEWS_ERROR___", "").sub("___", "")

      if defined?(Rails) && Rails.env.development?
        # Show error overlay in development
        error_content = ReactiveViews::ErrorOverlay.generate(
          component_name: component_name,
          props: props,
          error: error_message
        )

        error_div = Nokogiri::XML::Node.new("div", node.document)
        error_div.inner_html = error_content
        node.replace(error_div)
      else
        # In production, render empty div with minimal error info
        fallback = Nokogiri::XML::Node.new("div", node.document)
        fallback["data-reactive-views-error"] = "true"
        fallback["data-component"] = component_name
        fallback["style"] = "display: none;"
        fallback.content = "<!-- Component #{component_name} failed to render -->"
        node.replace(fallback)
      end
    end

    private_class_method def self.to_pascal_case(name)
      # Convert lowercase nokogiri name back to PascalCase
      # examplehello -> ExampleHello
      # We capitalize the first letter and look for common component name patterns
      name.split(/[-_]/).map(&:capitalize).join
    end

    private_class_method def self.contains_pascal_case_tag?(html)
      html.match?(%r{<\s*[A-Z][a-zA-Z0-9]})
    end
  end
end
