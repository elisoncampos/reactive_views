# frozen_string_literal: true

# Load vite_rails to ensure ViteRails constant is available
begin
  require "vite_rails"
rescue LoadError
  # If vite_rails is not installed, the helper will show an appropriate error
end

module ReactiveViews
  class Railtie < Rails::Railtie
    initializer "reactive_views.helpers" do
      ActiveSupport.on_load(:action_view) do
        include ReactiveViewsHelper
      end
    end

    initializer "reactive_views.controller_props" do
      ActiveSupport.on_load(:action_controller) do
        require_relative "controller_props"
        include ReactiveViews::ControllerProps

        helper_method :reactive_view_props if respond_to?(:helper_method)
      end
    end

    # Register :tsx and :jsx MIME types and handler
    initializer "reactive_views.register_template_handlers", before: :load_config_initializers do
      # Register :tsx and :jsx as aliases for HTML so lookups and formats behave
      begin
        Mime::Type.register_alias "text/html", :tsx unless Mime::Type.lookup_by_extension(:tsx)
        Mime::Type.register_alias "text/html", :jsx unless Mime::Type.lookup_by_extension(:jsx)
      rescue StandardError
        # no-op if Mime::Type is unavailable
      end

      ActiveSupport.on_load(:action_view) do
        require_relative "template_handler"
        ActionView::Template.register_template_handler :tsx, ReactiveViews::TemplateHandler
        ActionView::Template.register_template_handler :jsx, ReactiveViews::TemplateHandler
      end
    end

    # Register custom resolver to support HTML -> TSX -> JSX lookup
    initializer "reactive_views.setup_resolver", after: :load_config_initializers do
      Rails.logger&.info("[ReactiveViews] Initializing resolver...")
      ActiveSupport.on_load(:action_controller) do
        require_relative "resolver"

        # Add the resolver for app/views
        views_path = Rails.root.join("app", "views")
        Rails.logger&.info("[ReactiveViews] Views path: #{views_path}")
        if Dir.exist?(views_path)
          Rails.logger&.info("[ReactiveViews] Prepending resolver for #{views_path}")
          prepend_view_path ReactiveViews::Resolver.new(views_path.to_s)
        else
          Rails.logger&.warn("[ReactiveViews] Views path does not exist!")
        end
      end
    end

    # Hook into ActionView to transform component tags in rendered HTML
    initializer "reactive_views.transform_components", after: :load_config_initializers do
      ActiveSupport.on_load(:action_controller) do
        ActionController::Base.class_eval do
          around_action :transform_reactive_views_components

          private

          def transform_reactive_views_components
            yield  # Let controller exceptions bubble up naturally to rescue_from handlers

            # Only transform HTML responses
            if response.content_type&.include?("text/html") && response.body.present?
              begin
                response.body = ReactiveViews::TagTransformer.transform(response.body)
              rescue StandardError => e
                # Log transformation errors but don't break the response
                Rails.logger&.error("[ReactiveViews] Transformation error: #{e.message}")
                Rails.logger&.error(e.backtrace.join("\n")) if e.backtrace
              end
            end
          end
        end
      end
    end
  end
end
