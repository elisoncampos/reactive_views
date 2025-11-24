# frozen_string_literal: true

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root 'pages#home'
  get '/pages/home', to: 'pages#home'
  get '/pages/interactive', to: 'pages#interactive'
  get '/pages/jsx_test', to: 'pages#jsx_test'
  get '/pages/full_page_tsx', to: 'pages#full_page_tsx'
  get '/pages/full_page_jsx', to: 'pages#full_page_jsx'
  get '/pages/hooks_playground_tsx', to: 'pages#hooks_playground_tsx'
  get '/pages/hooks_playground_jsx', to: 'pages#hooks_playground_jsx'
  get '/pages/auto_runtime', to: 'pages#auto_runtime'
  get '/pages/layout_hooks', to: 'pages#layout_hooks'

  # Test routes for integration specs
  get '/with_component', to: 'test#with_component'
  get '/with_error', to: 'test#with_error'
  get '/interactive', to: 'test#interactive'
  get '/counter', to: 'test#counter'
  get '/hooks_playground', to: 'test#hooks_playground'

  # Routes for tsx partial composition tests
  get '/users', to: 'users#index'
  get '/users/:id', to: 'users#show', as: :user
end
