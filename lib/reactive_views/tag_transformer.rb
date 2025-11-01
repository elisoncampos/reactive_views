# frozen_string_literal: true

require "nokogiri"
require "securerandom"
require "json"

module ReactiveViews
  class TagTransformer
    # Transform HTML containing React component tags into SSR'd islands
    # Example: <PostList posts='[...]' /> becomes a hydration island
    def self.transform(html)
      return html unless ReactiveViews.config.enabled
      return html if html.nil? || html.empty?

      # Extract original component names before Nokogiri lowercases them
      component_name_map = extract_component_names(html)

      return html if component_name_map.empty?

      doc = Nokogiri::HTML5.fragment(html)

      # Find all custom component tags (PascalCase elements)
      component_nodes = find_component_nodes(doc)

      return html if component_nodes.empty?

      # Transform each component tag
      component_nodes.each do |node|
        transform_component_node(node, component_name_map)
      end

      doc.to_html
    rescue StandardError => e
      # Log error but return original HTML to avoid breaking the page
      if defined?(Rails) && Rails.logger
        Rails.logger.error("[ReactiveViews] TagTransformer error: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
      end
      html
    end

    private_class_method def self.extract_component_names(html)
      # Find all React component tags (PascalCase) before Nokogiri lowercases them
      # Matches: <ComponentName ...> or <ComponentName/>
      component_map = {}
      html.scan(/<([A-Z][a-zA-Z0-9]*)[\s\/>]/) do |match|
        component_name = match[0]
        component_map[component_name.downcase] = component_name
      end
      component_map
    end

    private_class_method def self.find_component_nodes(doc)
      # Nokogiri HTML5 lowercases all tag names, so we need to find custom elements
      # that don't match standard HTML tags. We look for tags that:
      # 1. Contain lowercase letters (Nokogiri normalized from PascalCase)
      # 2. Are not standard HTML elements
      # 3. Don't start with "reactive_views_" (our internal markers)

      standard_html_tags = %w[
        a abbr address area article aside audio b base bdi bdo blockquote body br
        button canvas caption cite code col colgroup data datalist dd del details
        dfn dialog div dl dt em embed fieldset figcaption figure footer form h1 h2
        h3 h4 h5 h6 head header hgroup hr html i iframe img input ins kbd label
        legend li link main map mark meta meter nav noscript object ol optgroup
        option output p param picture pre progress q rp rt ruby s samp script
        section select small source span strong style sub summary sup table tbody
        td template textarea tfoot th thead time title tr track u ul var video wbr
      ]

      doc.css("*").select do |node|
        # Skip if it's a standard HTML tag or our internal marker
        next false if standard_html_tags.include?(node.name.downcase)
        next false if node.name.downcase.start_with?("reactive_views_")

        # It's a custom element - likely a React component
        true
      end
    end

    private_class_method def self.transform_component_node(node, component_name_map)
      # Get the original PascalCase name from our map
      component_name = component_name_map[node.name.downcase] || to_pascal_case(node.name)
      uuid = SecureRandom.uuid

      # Extract props from attributes
      props = extract_props(node)

      # Render component via SSR
      ssr_html = ReactiveViews::Renderer.render(component_name, props)

      # Check for error marker
      if ssr_html.start_with?("___REACTIVE_VIEWS_ERROR___")
        handle_ssr_error(node, component_name, props, ssr_html)
        return
      end

      # Create the island container
      create_island(node, component_name, uuid, props, ssr_html)
    end

    private_class_method def self.extract_props(node)
      props = {}

      node.attributes.each do |name, attr|
        value = attr.value

        # Try to parse as JSON if it looks like JSON
        if value.start_with?("{", "[") || value == "true" || value == "false" || value =~ /^\d+$/
          begin
            props[name] = JSON.parse(value)
          rescue JSON::ParserError
            props[name] = value
          end
        else
          props[name] = value
        end
      end

      props
    end

    private_class_method def self.create_island(node, component_name, uuid, props, ssr_html)
      # Create container div
      container = Nokogiri::XML::Node.new("div", node.document)
      container["data-island-uuid"] = uuid
      container["data-component"] = component_name

      # Add SSR'd HTML as inner content
      container.inner_html = ssr_html

      # Create props script tag
      script = Nokogiri::XML::Node.new("script", node.document)
      script["type"] = "application/json"
      script["data-island-uuid"] = uuid
      script.content = props.to_json

      # Replace the original node
      node.add_next_sibling(script)
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
  end
end
