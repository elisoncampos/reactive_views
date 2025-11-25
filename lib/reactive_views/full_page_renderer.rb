# frozen_string_literal: true

require "json"
require "erb"

module ReactiveViews
  # Renders full-page TSX.ERB templates via ERB→TSX→SSR pipeline
  class FullPageRenderer
    require "securerandom"

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

        render_content(controller, tsx_content, extension: extension, identifier: template_full_path)
      end

      # Render from raw content (used by TemplateHandler)
      #
      # @param controller [ActionController::Base] The controller instance
      # @param content [String] The TSX/JSX content
      # @param extension [String] 'tsx' or 'jsx'
      # @return [String] SSR HTML
      def render_content(controller, content, extension: "tsx", identifier: nil)
        sanitized_content = sanitize_jsx_content(content)

        temp_file = TempFileManager.write(
          sanitized_content,
          identifier: identifier || controller.controller_name,
          extension: extension
        )

        props = PropsBuilder.build(controller.view_context, sanitized_content, extension: extension)

        render_result = Renderer.render_path_with_metadata(temp_file.path, props)
        html = render_result[:html]
        bundle_key = render_result[:bundle_key]

        # Check for error marker and show fullscreen overlay in development
        if html.to_s.start_with?("___REACTIVE_VIEWS_ERROR___")
          error_message = html.sub("___REACTIVE_VIEWS_ERROR___", "").sub(/___\z/, "")
          component_name = identifier ? File.basename(identifier.to_s, ".*") : "FullPage"
          return ErrorOverlay.generate_fullscreen(
            component_name: component_name,
            props: props,
            errors: [ { message: error_message } ]
          )
        end

        return html if bundle_key.nil?

        wrap_with_hydration(html, props, bundle_key)
      ensure
        temp_file&.delete
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

      def sanitize_jsx_content(content)
        return "" if content.nil?

        source = content.respond_to?(:to_str) ? content.to_str : content.to_s
        return source unless source.include?("<!--")

        source.gsub(/<!--\s*(BEGIN|END)\s+app\/views.*?-->\s*/m, "")
      end

      def wrap_with_hydration(html, props, bundle_key)
        uuid = SecureRandom.uuid
        metadata = {
          props: props || {},
          bundle: bundle_key
        }
        metadata_json = JSON.generate(metadata).gsub("</", "<\\/")

        container = %(<div data-reactive-page="true" data-page-uuid="#{uuid}">#{html}</div>)
        props_script = %(<script type="application/json" data-page-uuid="#{uuid}">#{metadata_json}</script>)

        "#{container}#{props_script}"
      end
    end
  end
end
