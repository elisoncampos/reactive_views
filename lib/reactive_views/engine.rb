# frozen_string_literal: true

module ReactiveViews
  class Engine < ::Rails::Engine
    isolate_namespace ReactiveViews

    # Mount the engine routes at /reactive_views
    initializer "reactive_views.routes" do |app|
      app.routes.prepend do
        mount ReactiveViews::Engine, at: "/reactive_views"
      end
    end
  end
end

