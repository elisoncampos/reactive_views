Rails.application.routes.draw do
  root "pages#home"
  get "/pages/home", to: "pages#home"
  get "/pages/interactive", to: "pages#interactive"

  # Test routes for integration specs
  get "/with_component", to: "test#with_component"
  get "/with_error", to: "test#with_error"
  get "/interactive", to: "test#interactive"
  get "/counter", to: "test#counter"

  # Routes for tsx partial composition tests
  get "/users", to: "users#index"
  get "/users/:id", to: "users#show", as: :user
end
