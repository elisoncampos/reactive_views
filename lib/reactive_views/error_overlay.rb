# frozen_string_literal: true

module ReactiveViews
  class ErrorOverlay
    def self.generate(component_name:, props:, error:)
      error_class, error_message = error.split(":", 2)
      error_message ||= error

      <<~HTML
        <div style="
          background: #1e1e1e;
          border: 2px solid #ef4444;
          border-radius: 8px;
          margin: 16px 0;
          padding: 24px;
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
          color: #e5e5e5;
          box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.5);
        ">
          <div style="display: flex; align-items: start; gap: 12px; margin-bottom: 16px;">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#ef4444" stroke-width="2" style="flex-shrink: 0; margin-top: 2px;">
              <circle cx="12" cy="12" r="10"></circle>
              <line x1="12" y1="8" x2="12" y2="12"></line>
              <line x1="12" y1="16" x2="12.01" y2="16"></line>
            </svg>
            <div style="flex: 1;">
              <h3 style="
                margin: 0 0 8px 0;
                font-size: 18px;
                font-weight: 600;
                color: #ef4444;
              ">ReactiveViews SSR Error</h3>
              <p style="margin: 0; font-size: 14px; color: #a3a3a3;">
                Failed to render component <strong style="color: #60a5fa;">&lt;#{escape_html(component_name)} /&gt;</strong>
              </p>
            </div>
          </div>

          <div style="
            background: #0a0a0a;
            border: 1px solid #404040;
            border-radius: 6px;
            padding: 16px;
            margin-bottom: 16px;
            font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            font-size: 13px;
            overflow-x: auto;
          ">
            <div style="color: #ef4444; font-weight: 600; margin-bottom: 8px;">
              #{escape_html(error_class)}
            </div>
            <div style="color: #e5e5e5; white-space: pre-wrap; word-break: break-word;">
              #{escape_html(error_message.strip)}
            </div>
          </div>

          #{props_section(props)}
          #{suggestions_section(error_message)}

          <div style="
            margin-top: 16px;
            padding-top: 16px;
            border-top: 1px solid #404040;
            font-size: 12px;
            color: #737373;
          ">
            <p style="margin: 0;">
              💡 This error overlay is only shown in development mode.
              In production, the component will fail silently.
            </p>
          </div>
        </div>
      HTML
    end

    private_class_method def self.props_section(props)
      return "" if props.nil? || props.empty?

      props_json = JSON.pretty_generate(props)

      <<~HTML
        <details style="margin-bottom: 16px;">
          <summary style="
            cursor: pointer;
            font-weight: 600;
            font-size: 14px;
            color: #a3a3a3;
            margin-bottom: 8px;
            user-select: none;
          ">
            Component Props
          </summary>
          <div style="
            background: #0a0a0a;
            border: 1px solid #404040;
            border-radius: 6px;
            padding: 16px;
            margin-top: 8px;
            font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            font-size: 13px;
            overflow-x: auto;
          ">
            <pre style="margin: 0; color: #22d3ee;">#{escape_html(props_json)}</pre>
          </div>
        </details>
      HTML
    end

    private_class_method def self.suggestions_section(error_message)
      suggestions = generate_suggestions(error_message)
      return "" if suggestions.empty?

      suggestions_html = suggestions.map do |suggestion|
        <<~HTML
          <li style="margin-bottom: 8px; padding-left: 8px;">
            #{escape_html(suggestion)}
          </li>
        HTML
      end.join

      <<~HTML
        <div style="
          background: #1a1a2e;
          border: 1px solid #3b82f6;
          border-radius: 6px;
          padding: 16px;
          margin-bottom: 16px;
        ">
          <div style="
            font-weight: 600;
            font-size: 14px;
            color: #60a5fa;
            margin-bottom: 12px;
          ">
            💡 Suggestions:
          </div>
          <ul style="
            margin: 0;
            padding-left: 20px;
            color: #e5e5e5;
            font-size: 14px;
            line-height: 1.6;
          ">
            #{suggestions_html}
          </ul>
        </div>
      HTML
    end

    private_class_method def self.generate_suggestions(error_message)
      suggestions = []

      if error_message.include?("Could not connect") || error_message.include?("ECONNREFUSED")
        suggestions << "Make sure the SSR server is running on #{ReactiveViews.config.ssr_url}"
        suggestions << "Check that 'bin/dev' or 'bundle exec rake reactive_views:ssr' is running"
        suggestions << "Verify the RV_SSR_PORT environment variable is set correctly"
      elsif error_message.include?("Component not found")
        suggestions << "Verify the component file exists in app/views/components/ or app/javascript/components/"
        suggestions << "Check that the component filename matches the PascalCase name (e.g., ExampleHello → example_hello.tsx)"
        suggestions << "Ensure the component has a default export"
      elsif error_message.include?("timed out")
        suggestions << "The SSR server might be overloaded or the component is taking too long to render"
        suggestions << "Check for infinite loops or slow computations in the component"
        suggestions << "Try increasing the timeout in config/initializers/reactive_views.rb"
      elsif error_message.include?("Invalid JSON")
        suggestions << "Check that the component props are valid JSON"
        suggestions << "Ensure special characters in props are properly escaped"
      else
        suggestions << "Check the SSR server logs for more details"
        suggestions << "Verify the component renders correctly in isolation"
        suggestions << "Review the component's props and ensure they match the expected types"
      end

      suggestions
    end

    private_class_method def self.escape_html(text)
      text.to_s
          .gsub("&", "&amp;")
          .gsub("<", "&lt;")
          .gsub(">", "&gt;")
          .gsub('"', "&quot;")
          .gsub("'", "&#39;")
    end
  end
end
