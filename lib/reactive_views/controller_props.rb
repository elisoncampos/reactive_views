# frozen_string_literal: true

module ReactiveViews
  # Controller mixin for explicit props to pass to full-page TSX rendering
  module ControllerProps
    # Deep-merges props to be passed to full-page TSX rendering alongside instance variables
    # Can be called multiple times; values are deep-merged
    #
    # @param hash [Hash] Props to merge
    # @return [Hash] Current merged props
    #
    # @example
    #   class UsersController < ApplicationController
    #     before_action -> { reactive_view_props(current_user: current_user) }
    #
    #     def index
    #       @users = User.all
    #       reactive_view_props(page: { title: "Users" })
    #     end
    #   end
    def reactive_view_props(hash = nil)
      @_reactive_view_props ||= {}
      @_reactive_view_props = deep_merge(@_reactive_view_props, hash.deep_symbolize_keys) if hash
      @_reactive_view_props
    end

    # Alias for convenience
    alias reactive_props reactive_view_props

    private

    # Deep merge two hashes
    def deep_merge(hash, other_hash)
      hash.merge(other_hash) do |_key, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          deep_merge(old_val, new_val)
        else
          new_val
        end
      end
    end
  end
end
