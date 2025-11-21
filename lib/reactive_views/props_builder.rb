# frozen_string_literal: true

require "set"

module ReactiveViews
  class PropsBuilder
    class << self
      def build(view_context, content, extension: "tsx")
        controller = view_context.controller

        # Collect instance variables
        assigns = view_context.assigns.deep_symbolize_keys

        # Merge with explicit reactive_view_props
        explicit_props = if controller.respond_to?(:reactive_view_props, true)
                           controller.send(:reactive_view_props)
        else
                           {}
        end

        all_props = assigns.merge(explicit_props)

        return all_props unless ReactiveViews.config.props_inference_enabled

        # Infer which props the component actually needs
        inferred_keys = PropsInference.infer_props(content, extension: extension)

        # If inference succeeded, filter to only inferred keys ∪ explicit keys
        if inferred_keys.any?
          inferred_set = inferred_keys.map(&:to_sym).to_set
          explicit_set = explicit_props.keys.to_set
          allowed_keys = inferred_set | explicit_set

          all_props.select { |key, _| allowed_keys.include?(key) }
        else
          # On inference failure, pass all props
          all_props
        end
      end
    end
  end
end
