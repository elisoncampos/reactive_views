# frozen_string_literal: true

# Load vite_rails to ensure ViteRails constant is available
begin
  require 'vite_rails'
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

    # Hook into ActionView to transform component tags in rendered HTML
    initializer "reactive_views.transform_components", after: :load_config_initializers do
      ActiveSupport.on_load(:action_controller) do
        ActionController::Base.class_eval do
          around_action :transform_reactive_views_components

          private

          def transform_reactive_views_components
            yield

            # Only transform HTML responses
            if response.content_type&.include?("text/html") && response.body.present?
              response.body = ReactiveViews::TagTransformer.transform(response.body)
            end
          rescue StandardError => e
            # Log error but don't break the response
            Rails.logger.error("[ReactiveViews] Transformation error: #{e.message}") if Rails.logger
            Rails.logger.error(e.backtrace.join("\n")) if Rails.logger && e.backtrace
          end
        end
      end
    end
  end
end
