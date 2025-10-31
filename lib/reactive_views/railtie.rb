# frozen_string_literal: true

module ReactiveViews
  class Railtie < Rails::Railtie
    initializer "reactive_views.helpers" do
      ActiveSupport.on_load(:action_view) do
        include ReactiveViewsHelper
      end
    end
  end
end
