# frozen_string_literal: true

require "action_view"

module ReactiveViews
  class Resolver < ActionView::FileSystemResolver
    private

    def _find_all(name, prefix, partial, details, key, locals)
      templates = super
      return templates if templates.any?
      return [] unless ReactiveViews.config.full_page_enabled
      return [] unless html_request?(details)

      search_reactive_template(name, prefix, partial, details)
    end

    def search_reactive_template(name, prefix, partial, details)
      base_path = base_directory(prefix)
      logical_name = partial ? "_#{name}" : name

      %w[tsx jsx].each do |ext|
        [
          File.join(base_path, "#{logical_name}.#{ext}.erb"),
          File.join(base_path, "#{logical_name}.#{ext}")
        ].each do |candidate|
          return [ build_reactive_template(candidate, prefix, name, partial, details) ] if File.exist?(candidate)
        end
      end

      []
    end

    def build_reactive_template(path, prefix, name, partial, details)
      source = File.binread(path)
      virtual_path = virtual_path_for(prefix, name, partial)
      variant = Array(details[:variants]).first

      ActionView::Template.new(
        source,
        path,
        ReactiveViews::TemplateHandler,
        virtual_path: virtual_path,
        format: :html,
        variant: variant,
        locals: []
      )
    end

    def base_directory(prefix)
      cleaned_prefix = prefix.to_s
      cleaned_prefix.empty? ? @path : File.join(@path, cleaned_prefix)
    end

    def virtual_path_for(prefix, name, partial)
      segments = []
      segments << prefix unless prefix.to_s.empty?
      segments << (partial ? "_#{name}" : name)
      segments.join("/")
    end

    def html_request?(details)
      Array(details[:formats]).include?(:html)
    end
  end
end
