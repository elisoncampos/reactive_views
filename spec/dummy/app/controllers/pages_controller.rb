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

  def jsx_test
    @message = "Hello from JSX!"
  end
end
