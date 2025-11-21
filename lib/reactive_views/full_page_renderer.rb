# frozen_string_literal: true

require "fileutils"
require "digest"
require "securerandom"

module ReactiveViews
  # Renders full-page TSX.ERB templates via ERB→TSX→SSR pipeline
  class FullPageRenderer
    class << self
      # Render a full-page TSX.ERB template
      #
      # @param controller [ActionController::Base] The controller instance
      # @param template_full_path [String] Full path to .tsx.erb template
      # @return [String] SSR HTML
      def render(controller, template_full_path:)
        # Step 1: Render ERB to produce TSX
        tsx_content = render_erb(controller, template_full_path)

        # Determine extension from path
        extension = template_full_path.to_s.end_with?(".jsx.erb") ? "jsx" : "tsx"

        render_content(controller, tsx_content, extension: extension)
      end

      # Render from raw content (used by TemplateHandler)
      #
      # @param controller [ActionController::Base] The controller instance
      # @param content [String] The TSX/JSX content
      # @param extension [String] 'tsx' or 'jsx'
      # @return [String] SSR HTML
      def render_content(controller, content, extension: "tsx")
        sanitized_content = sanitize_jsx_content(content)

        # Step 2: Write content to temporary file
        temp_path = write_temp_file(sanitized_content, extension)

        # Step 3: Build props from instance variables + explicit props
        props = build_props(controller, sanitized_content, extension)

        # Step 4: SSR the file
        html = Renderer.render_path(temp_path, props)

        html
      ensure
        # Clean up temp file
        File.delete(temp_path) if temp_path && File.exist?(temp_path)
      end

      private

      def render_erb(controller, template_path)
        # Create a view context with the controller's instance variables
        view_context = controller.view_context

        # CRITICAL: Set the lookup context to use :tsx format so partials resolve correctly
        # This ensures that when ERB processes <%= render "users/filters" %>, it looks for _filters.tsx.erb
        # Only modify lookup_context if it exists (may be a mock in tests)
        if view_context.respond_to?(:lookup_context) && view_context.lookup_context
          original_formats = view_context.lookup_context.formats.dup
          original_handlers = view_context.lookup_context.handlers.dup

          begin
            # Set formats to include :tsx so partials are found
            view_context.lookup_context.formats = %i[tsx html]
            # Ensure :tsx handler is in the lookup
            view_context.lookup_context.handlers = %i[tsx erb raw html builder ruby]

            # Read the template source
            template_source = File.read(template_path)

            # Render ERB with [:tsx] format so partials resolve correctly
            erb_handler = ActionView::Template.handler_for_extension("erb")

            # Create a temporary template object
            # Note: template_path must be a String, not Pathname
            template = ActionView::Template.new(
              template_source,
              template_path.to_s,
              erb_handler,
              locals: [],
              format: :tsx,
              variant: nil,
              virtual_path: nil
            )

            # Render the template in the view context
            template.render(view_context, {})
          ensure
            # Restore original lookup context
            view_context.lookup_context.formats = original_formats
            view_context.lookup_context.handlers = original_handlers
          end
        else
          # Fallback for mocks or when lookup_context is not available
          # Read the template source
          template_source = File.read(template_path)

          # Render ERB with [:tsx] format so partials resolve correctly
          erb_handler = ActionView::Template.handler_for_extension("erb")

          # Create a temporary template object
          template = ActionView::Template.new(
            template_source,
            template_path.to_s,
            erb_handler,
            locals: [],
            format: :tsx,
            variant: nil,
            virtual_path: nil
          )

          # Render the template in the view context
          template.render(view_context, {})
        end
      end

      def write_temp_file(content, extension)
        temp_dir = if defined?(Rails)
                     Rails.root.join("tmp", "reactive_views_full_page")
        else
                     File.join(Dir.tmpdir, "reactive_views_full_page")
        end

        FileUtils.mkdir_p(temp_dir)

        # Generate unique filename
        timestamp = Time.now.to_i
        random = SecureRandom.hex(8)
        temp_path = File.join(temp_dir, "page_#{timestamp}_#{random}.#{extension}")

        File.write(temp_path, content)
        temp_path
      end

      def build_props(controller, content, extension = "tsx")
        # Collect instance variables from the controller
        assigns = controller.view_assigns.deep_symbolize_keys

        # Merge with explicit reactive_view_props
        explicit_props = if controller.respond_to?(:reactive_view_props, true)
                           controller.send(:reactive_view_props)
        else
                           {}
        end

        all_props = assigns.merge(explicit_props)

        # Infer which props the component actually needs
        # Pass extension to help with parsing
        inferred_keys = PropsInference.infer_props(content, extension: extension)

        # If inference succeeded, filter to only inferred keys ∪ explicit keys
        if inferred_keys.any?
          inferred_set = inferred_keys.map(&:to_sym).to_set
          explicit_set = explicit_props.keys.to_set
          allowed_keys = inferred_set | explicit_set

          all_props.select { |key, _| allowed_keys.include?(key) }
        else
          # On inference failure, pass all props
          all_props
        end
      end

      def sanitize_jsx_content(content)
        return "" if content.nil?

        source = content.respond_to?(:to_str) ? content.to_str : content.to_s
        return source unless source.include?("<!--")

        source.gsub(/<!--\s*(BEGIN|END)\s+app\/views.*?-->\s*/m, "")
      end
    end
  end
end
