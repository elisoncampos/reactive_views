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

  def shadcn_demo
    @title = "shadcn/ui Integration Test"
    @description = "Testing CVA, clsx, and tailwind-merge"
  end

  def turbo_mixed
    @react_count = 10
    @stimulus_count = 5
  end

  def turbo_frame_content
    @timestamp = Time.current.to_s
    render partial: 'test/turbo_frame_content', layout: false
  end
end
