# frozen_string_literal: true

module ReactiveViews
  class ErrorOverlay
    OVERLAY_ID = "reactive-views-error-overlay"
    BADGE_ID = "reactive-views-error-badge"
    CONTEXT_LINES = 5 # Lines to show before/after error

    # Generate fullscreen error overlay (Next.js 15 style)
    # @param component_name [String] The component that failed
    # @param props [Hash] The props passed to the component
    # @param errors [Array<Hash>] Array of error hashes with :message, :stack, :file, :line keys
    # @return [String] Full HTML page with error overlay
    def self.generate_fullscreen(component_name:, props:, errors:)
      errors = normalize_errors(errors, component_name)
      error_count = errors.size

      # Return injectable HTML - NOT a full document
      # This gets embedded in the host app's layout
      <<~HTML
        <div id="rv-error-root">
          <style>#{fullscreen_styles}</style>
          #{render_backdrop}
          #{render_overlay_container(errors, props)}
          #{render_badge(error_count)}
          <script>#{overlay_script(error_count)}</script>
        </div>
      HTML
    end

    # Generate inline error overlay (backward compatible)
    # @param component_name [String] The component that failed
    # @param props [Hash] The props passed to the component
    # @param error [String] The error message
    # @return [String] HTML for inline error display
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
            #{error_icon}
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
              This error overlay is only shown in development mode.
              In production, the component will fail silently.
            </p>
          </div>
        </div>
      HTML
    end

    class << self
      private

      def normalize_errors(errors, component_name)
        errors.map.with_index do |err, idx|
          message = err[:message] || err["message"] || "Unknown error"
          parsed = parse_error_location(message)

          {
            id: idx,
            component: component_name,
            message: message,
            display_message: parsed[:display_message],
            stack: err[:stack] || err["stack"],
            file: parsed[:source_file] || err[:file] || err["file"],
            tmp_file: parsed[:tmp_file],
            line: parsed[:line] || err[:line] || err["line"],
            column: parsed[:column]
          }
        end
      end

      # Parse error message to extract file location and map to source
      def parse_error_location(message)
        result = {
          display_message: message,
          source_file: nil,
          tmp_file: nil,
          line: nil,
          column: nil
        }

        # Match patterns like: file.tsx:8:55: ERROR: message
        # or: Build failed with 1 error:\nfile.tsx:8:55: ERROR: message
        location_match = message.match(/([^\s:]+\.(?:tsx|jsx|ts|js)):(\d+):(\d+):\s*(?:ERROR:\s*)?(.+)/m)

        if location_match
          file_path = location_match[1]
          result[:line] = location_match[2].to_i
          result[:column] = location_match[3].to_i
          result[:display_message] = location_match[4].strip

          # Check if it's a temp file and try to map to source
          if file_path.include?("reactive_views_full_page") || file_path.include?("reactive_views_ssr")
            result[:tmp_file] = file_path
            result[:source_file] = map_tmp_to_source(file_path)
          else
            result[:source_file] = file_path
          end
        end

        result
      end

      # Map a temp file path back to the original source file
      def map_tmp_to_source(tmp_path)
        # Extract the safe_identifier from the temp filename
        # Format: {safe_identifier}_{timestamp}_{random}.{ext}
        basename = File.basename(tmp_path)

        # Remove extension
        name_without_ext = basename.sub(/\.\w+$/, "")

        # Remove timestamp_random suffix (pattern: _\d+_[a-f0-9]+$)
        identifier = name_without_ext.sub(/_\d+_[a-f0-9]+$/, "")

        # Strategy 1: Search in Rails app directories for matching files
        found_file = search_for_source_file(identifier)
        return found_file if found_file

        # Strategy 2: Return a cleaned up version for display
        clean_display_path(identifier)
      end

      def search_for_source_file(identifier)
        return nil unless defined?(Rails) && Rails.root

        # Extract potential filename parts from identifier
        # e.g., "_Users_..._app_views_home_hydration_playground_tsx_erb"
        # We want to find: "hydration_playground.tsx.erb"

        rails_root = Rails.root.to_s

        # Look for patterns like _app_views_ or _app_javascript_components_
        if identifier =~ /_app_views_(.+)$/
          relative_part = Regexp.last_match(1)
          search_in_directory(File.join(rails_root, "app", "views"), relative_part)
        elsif identifier =~ /_app_javascript_components_(.+)$/
          relative_part = Regexp.last_match(1)
          search_in_directory(File.join(rails_root, "app", "javascript", "components"), relative_part)
        elsif identifier =~ /_app_javascript_(.+)$/
          relative_part = Regexp.last_match(1)
          search_in_directory(File.join(rails_root, "app", "javascript"), relative_part)
        end
      end

      def search_in_directory(base_dir, encoded_relative_path)
        return nil unless Dir.exist?(base_dir)

        # The encoded path has underscores for both directories and filename parts
        # e.g., "home_hydration_playground_tsx_erb" could be:
        #   - home/hydration_playground.tsx.erb
        #   - home/hydration/playground.tsx.erb
        #   - home_hydration_playground.tsx.erb

        # Extract extension parts from the end
        parts = encoded_relative_path.split("_")
        extensions = []

        # Collect extensions from the end (erb, tsx, jsx, ts, js)
        while parts.any? && %w[erb tsx jsx ts js].include?(parts.last)
          extensions.unshift(parts.pop)
        end

        extension_str = extensions.any? ? ".#{extensions.join('.')}" : ""

        # Now try different combinations of directory/filename splits
        find_file_recursive(base_dir, parts, extension_str)
      end

      def find_file_recursive(base_dir, parts, extension)
        return nil if parts.empty?

        # Try the parts as a filename with underscores preserved
        filename = "#{parts.join('_')}#{extension}"
        full_path = File.join(base_dir, filename)
        return full_path if File.exist?(full_path)

        # Try treating first part as a directory
        if parts.length > 1
          subdir = File.join(base_dir, parts.first)
          if Dir.exist?(subdir)
            result = find_file_recursive(subdir, parts[1..], extension)
            return result if result
          end
        end

        # Try combining first two parts with underscore as a directory name
        if parts.length > 2
          combined_dir = File.join(base_dir, "#{parts[0]}_#{parts[1]}")
          if Dir.exist?(combined_dir)
            result = find_file_recursive(combined_dir, parts[2..], extension)
            return result if result
          end
        end

        nil
      end

      def clean_display_path(identifier)
        # Convert _Users_..._app_views_home_hydration_playground_tsx_erb
        # to a readable display path: app/views/home/hydration_playground.tsx.erb

        # Try to extract the app-relative portion
        if identifier =~ /_app_(views|javascript)_(.+)$/
          type = Regexp.last_match(1)
          rest = Regexp.last_match(2)

          parts = rest.split("_")
          extensions = []

          # Collect extensions from the end
          while parts.any? && %w[erb tsx jsx ts js].include?(parts.last)
            extensions.unshift(parts.pop)
          end

          # For the remaining parts, assume last parts are the filename
          # This is a heuristic - we keep at least the last 2 parts as filename
          if parts.length > 2
            # Assume first parts are directories, last parts are filename
            # Try to be smart: common directories are short words
            dir_parts = []
            file_parts = []

            parts.each_with_index do |part, idx|
              # Heuristics: 'views', 'home', 'components' are likely directories
              # Longer combined names are likely filenames
              if idx < parts.length - 1 && %w[views home components layouts shared javascript].include?(part)
                dir_parts << part
              else
                file_parts << part
              end
            end

            # If we didn't identify any directory parts, use all but last as dirs
            if dir_parts.empty? && parts.length > 1
              dir_parts = parts[0...-1]
              file_parts = [ parts.last ]
            end

            filename = file_parts.join("_")
            filename += ".#{extensions.join('.')}" if extensions.any?

            if dir_parts.any?
              "app/#{type}/#{dir_parts.join('/')}/#{filename}"
            else
              "app/#{type}/#{filename}"
            end
          else
            filename = parts.join("_")
            filename += ".#{extensions.join('.')}" if extensions.any?
            "app/#{type}/#{filename}"
          end
        else
          # Fallback: just return the identifier with some cleanup
          identifier.gsub(/^_/, "").gsub(/_(\d+_[a-f0-9]+)?$/, "")
        end
      end

      def clean_identifier(identifier)
        # Delegate to clean_display_path for backward compatibility
        clean_display_path(identifier)
      end

      def legacy_clean_identifier(identifier)
        # Old method - kept for reference
        parts = identifier.split("_").reject(&:empty?)

        # Find "app" and show from there
        app_idx = parts.index("app")
        if app_idx
          display_parts = parts[app_idx..]
          # Try to add dots for extensions
          display_parts[-1] = display_parts[-1].sub(/^(\w+)(tsx|jsx|ts|js)$/, '\1.\2') if display_parts.any?
          display_parts.join("/")
        else
          identifier.gsub("_", "/")
        end
      end

      def fullscreen_styles
        <<~CSS
          /* All styles scoped to #rv-error-root to avoid conflicts with host app */
          #rv-error-root {
            position: fixed;
            inset: 0;
            z-index: 99999;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            font-size: 14px;
            line-height: 1.5;
            color: #e5e5e5;
            -webkit-font-smoothing: antialiased;
          }

          #rv-error-root.rv-hidden {
            display: none;
          }

          #rv-error-root * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
          }

          #rv-error-root .rv-backdrop {
            position: fixed;
            inset: 0;
            background: rgba(0, 0, 0, 0.92);
            z-index: 99998;
            pointer-events: auto;
          }

          #rv-error-root .rv-overlay {
            position: fixed;
            inset: 0;
            z-index: 99999;
            display: flex;
            flex-direction: column;
            overflow: hidden;
            pointer-events: auto;
          }

          #rv-error-root .rv-overlay.rv-hidden {
            display: none;
          }

          #rv-error-root .rv-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 16px 24px;
            background: #141414;
            border-bottom: 1px solid #2a2a2a;
            flex-shrink: 0;
          }

          #rv-error-root .rv-header-left {
            display: flex;
            align-items: center;
            gap: 12px;
          }

          #rv-error-root .rv-logo {
            display: flex;
            align-items: center;
            gap: 8px;
            font-weight: 600;
            font-size: 14px;
            color: #ef4444;
          }

          #rv-error-root .rv-error-count {
            background: #ef4444;
            color: white;
            padding: 2px 8px;
            border-radius: 10px;
            font-size: 12px;
            font-weight: 600;
          }

          #rv-error-root .rv-close-btn {
            background: transparent;
            border: 1px solid #404040;
            color: #a3a3a3;
            padding: 8px 16px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 13px;
            transition: all 0.15s ease;
          }

          #rv-error-root .rv-close-btn:hover {
            background: #2a2a2a;
            color: #e5e5e5;
            border-color: #525252;
          }

          #rv-error-root .rv-tabs {
            display: flex;
            gap: 4px;
            padding: 12px 24px;
            background: #0f0f0f;
            border-bottom: 1px solid #2a2a2a;
            overflow-x: auto;
            flex-shrink: 0;
          }

          #rv-error-root .rv-tab {
            background: transparent;
            border: 1px solid transparent;
            color: #737373;
            padding: 8px 16px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 13px;
            white-space: nowrap;
            transition: all 0.15s ease;
          }

          #rv-error-root .rv-tab:hover {
            color: #a3a3a3;
            background: #1a1a1a;
          }

          #rv-error-root .rv-tab.rv-active {
            background: #1f1f1f;
            color: #ef4444;
            border-color: #ef4444;
          }

          #rv-error-root .rv-content {
            flex: 1;
            overflow-y: auto;
            padding: 24px;
            background: #0a0a0a;
          }

          #rv-error-root .rv-error-panel {
            display: none;
            max-width: 900px;
            margin: 0 auto;
          }

          #rv-error-root .rv-error-panel.rv-active {
            display: block;
          }

          #rv-error-root .rv-error-title {
            display: flex;
            align-items: flex-start;
            gap: 16px;
            margin-bottom: 24px;
          }

          #rv-error-root .rv-error-icon {
            flex-shrink: 0;
            width: 40px;
            height: 40px;
            background: rgba(239, 68, 68, 0.15);
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
          }

          #rv-error-root .rv-error-info h2 {
            margin: 0 0 8px 0;
            font-size: 20px;
            font-weight: 600;
            color: #ef4444;
            line-height: 1.3;
          }

          #rv-error-root .rv-error-info p {
            margin: 0;
            font-size: 14px;
            color: #737373;
          }

          #rv-error-root .rv-error-info code {
            color: #60a5fa;
            background: #1a1a2e;
            padding: 2px 6px;
            border-radius: 4px;
            font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            font-size: 13px;
          }

          #rv-error-root .rv-code-frame {
            background: #0a0a0a;
            border: 1px solid #2a2a2a;
            border-radius: 8px;
            margin-bottom: 24px;
            overflow: hidden;
          }

          #rv-error-root .rv-code-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 12px 16px;
            background: #141414;
            border-bottom: 1px solid #2a2a2a;
            font-size: 13px;
            color: #737373;
          }

          #rv-error-root .rv-code-file {
            font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            color: #a3a3a3;
          }

          #rv-error-root .rv-code-file-link {
            color: #60a5fa;
          }

          #rv-error-root .rv-code-body {
            font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            font-size: 13px;
            line-height: 1.6;
            overflow-x: auto;
          }

          #rv-error-root .rv-code-line {
            display: flex;
            padding: 0 16px;
            min-height: 22px;
          }

          #rv-error-root .rv-code-line:hover {
            background: rgba(255, 255, 255, 0.03);
          }

          #rv-error-root .rv-code-line.rv-error-line {
            background: rgba(239, 68, 68, 0.15);
            border-left: 3px solid #ef4444;
            padding-left: 13px;
          }

          #rv-error-root .rv-line-number {
            color: #525252;
            min-width: 48px;
            padding-right: 16px;
            text-align: right;
            user-select: none;
            flex-shrink: 0;
          }

          #rv-error-root .rv-error-line .rv-line-number {
            color: #ef4444;
          }

          #rv-error-root .rv-line-content {
            color: #e5e5e5;
            white-space: pre;
            flex: 1;
          }

          /* Syntax highlighting */
          #rv-error-root .rv-keyword { color: #c678dd; }
          #rv-error-root .rv-string { color: #98c379; }
          #rv-error-root .rv-number { color: #d19a66; }
          #rv-error-root .rv-comment { color: #5c6370; font-style: italic; }
          #rv-error-root .rv-tag { color: #e06c75; }
          #rv-error-root .rv-attr { color: #d19a66; }
          #rv-error-root .rv-function { color: #61afef; }

          #rv-error-root .rv-error-message-box {
            background: #1a0a0a;
            border: 1px solid #ef4444;
            border-radius: 6px;
            padding: 12px 16px;
            margin: 12px 16px;
            font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            font-size: 13px;
            color: #ef4444;
          }

          #rv-error-root .rv-stack-trace {
            margin-bottom: 24px;
          }

          #rv-error-root .rv-stack-header {
            display: flex;
            align-items: center;
            gap: 8px;
            margin-bottom: 12px;
            font-size: 14px;
            font-weight: 600;
            color: #a3a3a3;
            cursor: pointer;
            user-select: none;
          }

          #rv-error-root .rv-stack-header:hover {
            color: #e5e5e5;
          }

          #rv-error-root .rv-stack-chevron {
            transition: transform 0.15s ease;
          }

          #rv-error-root .rv-stack-chevron.rv-open {
            transform: rotate(90deg);
          }

          #rv-error-root .rv-stack-content {
            background: #0a0a0a;
            border: 1px solid #2a2a2a;
            border-radius: 8px;
            padding: 16px;
            font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            font-size: 12px;
            line-height: 1.8;
            color: #a3a3a3;
            overflow-x: auto;
            white-space: pre-wrap;
            word-break: break-word;
            display: none;
          }

          #rv-error-root .rv-stack-content.rv-open {
            display: block;
          }

          #rv-error-root .rv-stack-frame {
            padding: 4px 0;
          }

          #rv-error-root .rv-stack-frame.rv-app-frame {
            color: #e5e5e5;
          }

          #rv-error-root .rv-suggestions {
            background: #0f172a;
            border: 1px solid #1e3a5f;
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 24px;
          }

          #rv-error-root .rv-suggestions-title {
            display: flex;
            align-items: center;
            gap: 8px;
            font-size: 14px;
            font-weight: 600;
            color: #60a5fa;
            margin-bottom: 16px;
          }

          #rv-error-root .rv-suggestions ul {
            margin: 0;
            padding-left: 20px;
            font-size: 14px;
            line-height: 1.8;
            color: #cbd5e1;
            list-style: disc;
          }

          #rv-error-root .rv-suggestions li {
            margin-bottom: 8px;
          }

          #rv-error-root .rv-props {
            margin-bottom: 24px;
          }

          #rv-error-root .rv-props-header {
            display: flex;
            align-items: center;
            gap: 8px;
            margin-bottom: 12px;
            font-size: 14px;
            font-weight: 600;
            color: #a3a3a3;
            cursor: pointer;
            user-select: none;
          }

          #rv-error-root .rv-props-header:hover {
            color: #e5e5e5;
          }

          #rv-error-root .rv-props-content {
            background: #0a0a0a;
            border: 1px solid #2a2a2a;
            border-radius: 8px;
            padding: 16px;
            font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            font-size: 13px;
            color: #22d3ee;
            overflow-x: auto;
            display: none;
            white-space: pre;
          }

          #rv-error-root .rv-props-content.rv-open {
            display: block;
          }

          /* Badge - always visible even when overlay hidden */
          #rv-error-root .rv-badge {
            position: fixed;
            bottom: 20px;
            right: 20px;
            z-index: 100000;
            display: flex;
            align-items: center;
            gap: 8px;
            background: #1f1f1f;
            border: 1px solid #ef4444;
            padding: 10px 16px;
            border-radius: 50px;
            cursor: pointer;
            font-size: 13px;
            font-weight: 500;
            color: #ef4444;
            box-shadow: 0 4px 20px rgba(239, 68, 68, 0.3);
            transition: all 0.2s ease;
            animation: rv-badge-pulse 2s ease-in-out infinite;
            pointer-events: auto;
          }

          #rv-error-root .rv-badge:hover {
            transform: scale(1.05);
            box-shadow: 0 6px 24px rgba(239, 68, 68, 0.4);
          }

          #rv-error-root .rv-badge.rv-hidden {
            display: none;
          }

          #rv-error-root .rv-badge-dot {
            width: 8px;
            height: 8px;
            background: #ef4444;
            border-radius: 50%;
            animation: rv-dot-pulse 1.5s ease-in-out infinite;
          }

          @keyframes rv-badge-pulse {
            0%, 100% { box-shadow: 0 4px 20px rgba(239, 68, 68, 0.3); }
            50% { box-shadow: 0 4px 30px rgba(239, 68, 68, 0.5); }
          }

          @keyframes rv-dot-pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
          }

          #rv-error-root .rv-footer {
            padding: 16px 24px;
            background: #0f0f0f;
            border-top: 1px solid #2a2a2a;
            text-align: center;
            font-size: 12px;
            color: #525252;
            flex-shrink: 0;
          }

          #rv-error-root .rv-footer a {
            color: #60a5fa;
            text-decoration: none;
          }

          #rv-error-root .rv-footer a:hover {
            text-decoration: underline;
          }
        CSS
      end

      def render_backdrop
        %(<div class="rv-backdrop" id="rv-backdrop"></div>)
      end

      def render_overlay_container(errors, props)
        tabs_html = render_tabs(errors)
        panels_html = errors.map { |err| render_error_panel(err, props) }.join

        <<~HTML
          <div class="rv-overlay" id="#{OVERLAY_ID}">
            <div class="rv-header">
              <div class="rv-header-left">
                <div class="rv-logo">
                  #{error_icon(20)}
                  <span>ReactiveViews Error</span>
                </div>
                <span class="rv-error-count">#{errors.size} #{errors.size == 1 ? 'error' : 'errors'}</span>
              </div>
              <button class="rv-close-btn" onclick="window.RVOverlay.hide()">
                Dismiss (Esc)
              </button>
            </div>
            #{tabs_html}
            <div class="rv-content">
              #{panels_html}
            </div>
            <div class="rv-footer">
              This error overlay is only shown in development mode.
              Press <strong>Esc</strong> to dismiss or click outside to close.
            </div>
          </div>
        HTML
      end

      def render_tabs(errors)
        return "" if errors.size <= 1

        tabs = errors.map.with_index do |err, idx|
          active_class = idx.zero? ? "rv-active" : ""
          error_preview = truncate_message(err[:display_message] || err[:message], 40)
          <<~HTML
            <button class="rv-tab #{active_class}" data-tab="#{idx}" onclick="window.RVOverlay.switchTab(#{idx})">
              #{idx + 1}. #{escape_html(error_preview)}
            </button>
          HTML
        end.join

        %(<div class="rv-tabs">#{tabs}</div>)
      end

      def render_error_panel(error, props)
        active_class = error[:id].zero? ? "rv-active" : ""
        display_message = error[:display_message] || error[:message]
        error_class, _error_detail = parse_error_message(display_message)

        <<~HTML
          <div class="rv-error-panel #{active_class}" data-panel="#{error[:id]}">
            <div class="rv-error-title">
              <div class="rv-error-icon">
                #{error_icon(24)}
              </div>
              <div class="rv-error-info">
                <h2>#{escape_html(error_class)}</h2>
                <p>Failed to render <code>&lt;#{escape_html(error[:component])} /&gt;</code></p>
              </div>
            </div>

            #{render_code_frame(error)}
            #{render_stack_trace(error)}
            #{render_suggestions(display_message)}
            #{render_props_section(props, error[:id])}
          </div>
        HTML
      end

      def render_code_frame(error)
        source_file = error[:file]
        line_number = error[:line]
        column = error[:column]
        display_message = error[:display_message] || error[:message]

        # Try to read the source file
        source_lines = read_source_file(source_file, line_number)

        if source_lines && source_lines.any?
          render_source_code_frame(source_file, source_lines, line_number, column, display_message)
        else
          render_fallback_code_frame(source_file, line_number, display_message)
        end
      end

      def read_source_file(file_path, error_line)
        return nil unless file_path && File.exist?(file_path)

        lines = File.readlines(file_path)
        error_line ||= 1
        start_line = [ error_line - CONTEXT_LINES, 1 ].max
        end_line = [ error_line + CONTEXT_LINES, lines.length ].min

        lines[(start_line - 1)..(end_line - 1)].map.with_index(start_line) do |content, num|
          { number: num, content: content.chomp, is_error: num == error_line }
        end
      rescue StandardError
        nil
      end

      def render_source_code_frame(file_path, source_lines, error_line, _column, display_message)
        # Format file path for display (make it relative if possible)
        display_path = format_file_path(file_path)
        line_info = error_line ? ":#{error_line}" : ""

        lines_html = source_lines.map do |line|
          line_class = line[:is_error] ? "rv-code-line rv-error-line" : "rv-code-line"
          highlighted_content = syntax_highlight(line[:content])

          <<~HTML
            <div class="#{line_class}">
              <span class="rv-line-number">#{line[:number]}</span>
              <span class="rv-line-content">#{highlighted_content}</span>
            </div>
          HTML
        end.join

        <<~HTML
          <div class="rv-code-frame">
            <div class="rv-code-header">
              <span class="rv-code-file">
                <span class="rv-code-file-link">#{escape_html(display_path)}#{line_info}</span>
              </span>
            </div>
            <div class="rv-code-body">
              #{lines_html}
            </div>
            <div class="rv-error-message-box">
              #{escape_html(display_message)}
            </div>
          </div>
        HTML
      end

      def render_fallback_code_frame(file_path, line_number, display_message)
        file_info = if file_path
                      line_number ? "#{file_path}:#{line_number}" : file_path
        else
                      "Component Source"
        end

        <<~HTML
          <div class="rv-code-frame">
            <div class="rv-code-header">
              <span class="rv-code-file">#{escape_html(file_info)}</span>
            </div>
            <div class="rv-code-body">
              <div class="rv-code-line rv-error-line">
                <span class="rv-line-content">#{escape_html(display_message)}</span>
              </div>
            </div>
          </div>
        HTML
      end

      def format_file_path(path)
        return path unless defined?(Rails)

        # Make path relative to Rails root for cleaner display
        rails_root = Rails.root.to_s
        if path.start_with?(rails_root)
          path.sub("#{rails_root}/", "")
        else
          path
        end
      end

      def syntax_highlight(code)
        return "" if code.nil?

        # Use a single-pass tokenizer approach to avoid regex conflicts
        # We'll tokenize first, then reconstruct with highlighting

        tokens = tokenize_code(code)
        tokens.map { |token| render_token(token) }.join
      end

      def tokenize_code(code)
        tokens = []
        pos = 0

        while pos < code.length
          # Try to match patterns in order of specificity
          matched = false

          # Comments: // to end of line
          if code[pos..] =~ /\A(\/\/[^\n]*)/
            tokens << { type: :comment, value: Regexp.last_match(1) }
            pos += Regexp.last_match(1).length
            matched = true
          # Strings: double quotes
          elsif code[pos..] =~ /\A("(?:[^"\\]|\\.)*")/
            tokens << { type: :string, value: Regexp.last_match(1) }
            pos += Regexp.last_match(1).length
            matched = true
          # Strings: single quotes
          elsif code[pos..] =~ /\A('(?:[^'\\]|\\.)*')/
            tokens << { type: :string, value: Regexp.last_match(1) }
            pos += Regexp.last_match(1).length
            matched = true
          # Strings: template literals (simplified)
          elsif code[pos..] =~ /\A(`[^`]*`)/
            tokens << { type: :string, value: Regexp.last_match(1) }
            pos += Regexp.last_match(1).length
            matched = true
          # JSX tags: <tagname or </tagname
          elsif code[pos..] =~ /\A(<\/?)([\w]+)/
            tokens << { type: :plain, value: Regexp.last_match(1) }
            tokens << { type: :tag, value: Regexp.last_match(2) }
            pos += Regexp.last_match(0).length
            matched = true
          # Keywords (must be word boundaries)
          elsif code[pos..] =~ /\A\b(import|export|default|from|const|let|var|function|return|if|else|for|while|class|extends|implements|interface|type|async|await|try|catch|throw|new|typeof)\b/
            tokens << { type: :keyword, value: Regexp.last_match(1) }
            pos += Regexp.last_match(1).length
            matched = true
          # Numbers
          elsif code[pos..] =~ /\A\b(\d+\.?\d*)\b/
            tokens << { type: :number, value: Regexp.last_match(1) }
            pos += Regexp.last_match(1).length
            matched = true
          # Function calls: word followed by (
          elsif code[pos..] =~ /\A\b([\w]+)(\()/
            tokens << { type: :function, value: Regexp.last_match(1) }
            tokens << { type: :plain, value: Regexp.last_match(2) }
            pos += Regexp.last_match(0).length
            matched = true
          end

          # If no pattern matched, consume one character as plain text
          unless matched
            # Accumulate plain text
            if tokens.any? && tokens.last[:type] == :plain
              tokens.last[:value] += code[pos]
            else
              tokens << { type: :plain, value: code[pos] }
            end
            pos += 1
          end
        end

        tokens
      end

      def render_token(token)
        escaped_value = escape_html(token[:value])

        case token[:type]
        when :comment
          %(<span class="rv-comment">#{escaped_value}</span>)
        when :string
          %(<span class="rv-string">#{escaped_value}</span>)
        when :tag
          %(<span class="rv-tag">#{escaped_value}</span>)
        when :keyword
          %(<span class="rv-keyword">#{escaped_value}</span>)
        when :number
          %(<span class="rv-number">#{escaped_value}</span>)
        when :function
          %(<span class="rv-function">#{escaped_value}</span>)
        else
          escaped_value
        end
      end

      def render_stack_trace(error)
        return "" unless error[:stack]

        stack_id = "stack-#{error[:id]}"
        formatted_stack = format_stack_trace(error[:stack])

        <<~HTML
          <div class="rv-stack-trace">
            <div class="rv-stack-header" onclick="window.RVOverlay.toggleStack('#{stack_id}')">
              <span class="rv-stack-chevron" id="#{stack_id}-chevron">▶</span>
              <span>Call Stack</span>
            </div>
            <div class="rv-stack-content" id="#{stack_id}">
              #{formatted_stack}
            </div>
          </div>
        HTML
      end

      def render_suggestions(error_message)
        suggestions = generate_suggestions(error_message)
        return "" if suggestions.empty?

        suggestions_html = suggestions.map { |s| "<li>#{escape_html(s)}</li>" }.join

        <<~HTML
          <div class="rv-suggestions">
            <div class="rv-suggestions-title">
              #{lightbulb_icon}
              <span>Suggestions</span>
            </div>
            <ul>#{suggestions_html}</ul>
          </div>
        HTML
      end

      def render_props_section(props, error_id)
        return "" if props.nil? || props.empty?

        props_id = "props-#{error_id}"
        props_json = JSON.pretty_generate(props)

        <<~HTML
          <div class="rv-props">
            <div class="rv-props-header" onclick="window.RVOverlay.toggleProps('#{props_id}')">
              <span class="rv-stack-chevron" id="#{props_id}-chevron">▶</span>
              <span>Component Props</span>
            </div>
            <pre class="rv-props-content" id="#{props_id}">#{escape_html(props_json)}</pre>
          </div>
        HTML
      end

      def render_badge(error_count)
        label = error_count == 1 ? "1 error" : "#{error_count} errors"

        <<~HTML
          <div class="rv-badge rv-hidden" id="#{BADGE_ID}" onclick="window.RVOverlay.show()">
            <span class="rv-badge-dot"></span>
            <span>#{label}</span>
          </div>
        HTML
      end

      def overlay_script(error_count)
        <<~JS
          (function() {
            window.RVOverlay = {
              errorCount: #{error_count},
              currentTab: 0,
              isVisible: true,

              show: function() {
                document.getElementById('#{OVERLAY_ID}').classList.remove('rv-hidden');
                document.getElementById('rv-backdrop').style.display = 'block';
                document.getElementById('#{BADGE_ID}').classList.add('rv-hidden');
                this.isVisible = true;
              },

              hide: function() {
                document.getElementById('#{OVERLAY_ID}').classList.add('rv-hidden');
                document.getElementById('rv-backdrop').style.display = 'none';
                document.getElementById('#{BADGE_ID}').classList.remove('rv-hidden');
                this.isVisible = false;
              },

              switchTab: function(index) {
                // Update tabs
                document.querySelectorAll('.rv-tab').forEach(function(tab, i) {
                  tab.classList.toggle('rv-active', i === index);
                });
                // Update panels
                document.querySelectorAll('.rv-error-panel').forEach(function(panel, i) {
                  panel.classList.toggle('rv-active', i === index);
                });
                this.currentTab = index;
              },

              toggleStack: function(id) {
                var content = document.getElementById(id);
                var chevron = document.getElementById(id + '-chevron');
                content.classList.toggle('rv-open');
                chevron.classList.toggle('rv-open');
              },

              toggleProps: function(id) {
                var content = document.getElementById(id);
                var chevron = document.getElementById(id + '-chevron');
                content.classList.toggle('rv-open');
                chevron.classList.toggle('rv-open');
              },

              nextError: function() {
                if (this.errorCount > 1) {
                  this.switchTab((this.currentTab + 1) % this.errorCount);
                }
              },

              prevError: function() {
                if (this.errorCount > 1) {
                  this.switchTab((this.currentTab - 1 + this.errorCount) % this.errorCount);
                }
              }
            };

            // Keyboard shortcuts
            document.addEventListener('keydown', function(e) {
              if (e.key === 'Escape') {
                window.RVOverlay.hide();
              } else if (e.key === 'ArrowRight' && window.RVOverlay.isVisible) {
                window.RVOverlay.nextError();
              } else if (e.key === 'ArrowLeft' && window.RVOverlay.isVisible) {
                window.RVOverlay.prevError();
              }
            });

            // Click outside to close
            document.getElementById('rv-backdrop').addEventListener('click', function() {
              window.RVOverlay.hide();
            });
          })();
        JS
      end

      def parse_error_message(error)
        parts = error.to_s.split(":", 2)
        if parts.size == 2
          [ parts[0].strip, parts[1].strip ]
        else
          [ "Error", error.to_s ]
        end
      end

      def format_stack_trace(stack)
        return "" unless stack

        lines = stack.to_s.split("\n").map do |line|
          is_app_frame = line.include?("app/") || line.include?("components/")
          frame_class = is_app_frame ? "rv-app-frame" : ""
          %(<div class="rv-stack-frame #{frame_class}">#{escape_html(line)}</div>)
        end

        lines.join
      end

      def truncate_message(message, max_length)
        return message if message.to_s.length <= max_length

        "#{message.to_s[0, max_length]}..."
      end

      def error_icon(size = 24)
        <<~SVG
          <svg width="#{size}" height="#{size}" viewBox="0 0 24 24" fill="none" stroke="#ef4444" stroke-width="2">
            <circle cx="12" cy="12" r="10"></circle>
            <line x1="12" y1="8" x2="12" y2="12"></line>
            <line x1="12" y1="16" x2="12.01" y2="16"></line>
          </svg>
        SVG
      end

      def lightbulb_icon
        <<~SVG
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M9 18h6M10 22h4M12 2v1M12 8a4 4 0 0 0-4 4c0 1.5.8 2.8 2 3.5V17h4v-1.5c1.2-.7 2-2 2-3.5a4 4 0 0 0-4-4Z"/>
          </svg>
        SVG
      end

      def props_section(props)
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

      def suggestions_section(error_message)
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
              Suggestions:
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

      def generate_suggestions(error_message)
        suggestions = []
        msg = error_message.to_s

        if msg.include?("Could not connect") || msg.include?("ECONNREFUSED")
          suggestions << "In development, ensure 'bin/dev' is running"
          suggestions << "In production, ReactiveViews auto-starts the SSR server - check log/reactive_views_ssr.log for errors"
          suggestions << "If managing SSR externally, verify RV_SSR_URL points to the correct address"
        elsif msg.include?("Component not found") || msg.include?("not found")
          suggestions << "Verify the component file exists in app/views/components/ or app/javascript/components/"
          suggestions << "Check that the component filename matches the PascalCase name (e.g., ExampleHello -> example_hello.tsx)"
          suggestions << "Ensure the component has a default export"
        elsif msg.include?("timed out")
          suggestions << "The SSR server might be overloaded or the component is taking too long to render"
          suggestions << "Check for infinite loops or slow computations in the component"
          suggestions << "Try increasing the timeout in config/initializers/reactive_views.rb"
        elsif msg.include?("Invalid JSON")
          suggestions << "Check that the component props are valid JSON"
          suggestions << "Ensure special characters in props are properly escaped"
        elsif msg.include?("SyntaxError") || msg.include?("Unexpected token") || msg.include?("Expected")
          suggestions << "Check for syntax errors in your component file"
          suggestions << "Verify all JSX tags are properly closed"
          suggestions << "Check for missing imports or typos in variable names"
          suggestions << "Look for mismatched brackets, parentheses, or braces"
        elsif msg.include?("TypeError") || msg.include?("is not a function")
          suggestions << "Check that all imported modules exist and are exported correctly"
          suggestions << "Verify that hooks are used inside functional components"
          suggestions << "Make sure you're not calling a non-function as a function"
        elsif msg.include?("ReferenceError") || msg.include?("is not defined")
          suggestions << "Check for undefined variables or missing imports"
          suggestions << "Verify the component is using the correct import paths"
          suggestions << "Make sure server-side code isn't accessing browser APIs"
        else
          suggestions << "Check the SSR server logs for more details"
          suggestions << "Verify the component renders correctly in isolation"
          suggestions << "Review the component's props and ensure they match the expected types"
        end

        suggestions
      end

      def escape_html(text)
        text.to_s
            .gsub("&", "&amp;")
            .gsub("<", "&lt;")
            .gsub(">", "&gt;")
            .gsub('"', "&quot;")
            .gsub("'", "&#39;")
      end
    end
  end
end
