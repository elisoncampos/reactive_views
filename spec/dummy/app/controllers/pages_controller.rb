# frozen_string_literal: true

class PagesController < ActionController::Base
  include ReactiveViewsHelper
  layout 'application'

  def home
    @page_title = 'Welcome to ReactiveViews'
    @users = [
      { id: 1, name: 'Alice', role: 'Developer' },
      { id: 2, name: 'Bob', role: 'Designer' },
      { id: 3, name: 'Charlie', role: 'Manager' }
    ]
    @current_user = { name: 'Test User', email: 'test@example.com' }
  end

  def interactive
    @page_title = 'Interactive Counter Test'
    @initial_count = 10
  end

  def full_page_tsx
    @page_title = 'Full Page TSX Counter'
    @initial_count = 7
    @effect_label = 'server'
  end

  def full_page_jsx
    @page_title = 'Full Page JSX Counter'
    @initial_count = 4
    @effect_label = 'server'
  end

  def hooks_playground_tsx
    @page_title = 'Hooks Playground TSX'
    @initial_count = 8
    @initial_label = 'full-tsx'
  end

  def hooks_playground_jsx
    @page_title = 'Hooks Playground JSX'
    @initial_count = 6
    @initial_label = 'full-jsx'
  end

  def auto_runtime
    @name = 'Hydration Playground'
    @counter = 16
  end

  def layout_hooks
    @layout_initial = 2
    @initial_count = 5
    @initial_label = 'layout-page'
  end

  def jsx_test
    @message = "Hello from JSX!"
  end
end
