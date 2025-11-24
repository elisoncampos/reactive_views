# frozen_string_literal: true

class TestController < ActionController::Base
  include ReactiveViewsHelper
  layout 'application'

  def with_component
    @message = 'Hello from TestController'
  end

  def with_error
    # This action will have a component that can't be resolved
  end

  def interactive
    @count = 10
  end

  def counter
    @initial_count = 5
  end

  def hooks_playground
    @tsx_initial = 3
    @jsx_initial = 2
  end
end
