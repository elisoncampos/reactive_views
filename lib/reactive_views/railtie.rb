# frozen_string_literal: true

# Load vite_rails to ensure ViteRails constant is available
begin
  require 'vite_rails'
rescue LoadError
  # If vite_rails is not installed, the helper will show an appropriate error
end

module ReactiveViews
  class Railtie < Rails::Railtie
    initializer 'reactive_views.helpers' do
      ActiveSupport.on_load(:action_view) do
        include ReactiveViewsHelper
      end
    end

    initializer 'reactive_views.controller_props' do
      ActiveSupport.on_load(:action_controller) do
        require_relative 'controller_props'
        include ReactiveViews::ControllerProps
        helper_method :reactive_view_props if respond_to?(:helper_method)
      end
    end

    # Register :tsx MIME type and handler
    initializer 'reactive_views.register_tsx_template_handler', before: :load_config_initializers do
      # Register :tsx as an alias for HTML so lookups and formats behave
      begin
        Mime::Type.register_alias 'text/html', :tsx unless Mime::Type.lookup_by_extension(:tsx)
      rescue StandardError
        # no-op if Mime::Type is unavailable or already registered
      end

      # Register .tsx.erb as a valid template handler
      ActiveSupport.on_load(:action_view) do
        ActionView::Template.register_template_handler :tsx, ActionView::Template.registered_template_handler(:erb)
      end
    end

    # Hook into ActionView to transform component tags in rendered HTML
    initializer 'reactive_views.transform_components', after: :load_config_initializers do
      ActiveSupport.on_load(:action_controller) do
        ActionController::Base.class_eval do
          around_action :transform_reactive_views_components

          private

          def transform_reactive_views_components
            yield

            # Only transform HTML responses
            if response.content_type&.include?('text/html') && response.body.present?
              response.body = ReactiveViews::TagTransformer.transform(response.body)
            end
          rescue StandardError => e
            # Don't catch template-related exceptions - let them bubble up to default_render override
            raise if e.is_a?(ActionView::MissingTemplate) ||
                     e.is_a?(ActionController::UnknownFormat) ||
                     e.is_a?(ActionController::MissingExactTemplate)

            # Log error but don't break the response
            Rails.logger&.error("[ReactiveViews] Transformation error: #{e.message}")
            Rails.logger.error(e.backtrace.join("\n")) if Rails.logger && e.backtrace
          end
        end
      end
    end

    # Fallback to full-page TSX.ERB when HTML template is missing
    # Using prepend ensures this wraps the existing transform_reactive_views_components
    initializer 'reactive_views.full_page_fallback', after: :load_config_initializers,
                                                     before: 'reactive_views.transform_components' do
      ActiveSupport.on_load(:action_controller) do
        require_relative 'full_page_renderer'

        # Override default_render to check for .tsx.erb before raising MissingTemplate
        ActionController::Base.class_eval do
          def default_render(*args)
            # First try the normal Rails template lookup

            super
          rescue ActionView::MissingTemplate, ActionController::UnknownFormat,
                 ActionController::MissingExactTemplate => exception
            # Only handle if full_page_enabled and HTML request
            raise exception unless ReactiveViews.config.full_page_enabled && request.format&.html?

            Rails.logger&.debug("[ReactiveViews] MissingTemplate caught in default_render: #{exception.message}")

            # Check for .tsx.erb fallback template
            template_path = Rails.root.join('app', 'views', controller_path, "#{action_name}.tsx.erb")
            Rails.logger&.debug("[ReactiveViews] Looking for fallback template at: #{template_path}")

            if File.exist?(template_path)
              Rails.logger&.debug('[ReactiveViews] Rendering full-page TSX.ERB')
              begin
                html = ReactiveViews::FullPageRenderer.render(self, template_full_path: template_path)
                Rails.logger&.debug("[ReactiveViews] Full-page rendered #{html.length} bytes")
                self.response_body = html
                self.status = 200
                self.content_type ||= 'text/html'
              rescue StandardError => e
                Rails.logger&.error("[ReactiveViews] Full-page render error: #{e.class}: #{e.message}")
                Rails.logger&.error(e.backtrace.join("\n"))
                raise exception
              end
            else
              Rails.logger&.debug('[ReactiveViews] TSX.ERB template not found, re-raising')
              raise exception
            end
          end
        end
      end
    end
  end
end
