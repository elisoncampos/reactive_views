# frozen_string_literal: true

module ReactiveViews
  class TemplateHandler
    class << self
      def call(template, source)
        extension = extract_extension(template.identifier)
        compiled_source = compiled_template_source(template, source)

        if partial_template?(template)
          compiled_source
        else
          <<-RUBY
          content = begin
            #{compiled_source}
          end
          ReactiveViews::FullPageRenderer.render_content(
            controller,
            content,
            extension: '#{extension}',
            identifier: #{template.identifier.inspect}
          )
          RUBY
        end
      end

      private

      def extract_extension(identifier)
        base = identifier.end_with?(".erb") ? File.basename(identifier, ".erb") : identifier
        ext = File.extname(base).delete(".")
        %w[tsx jsx].include?(ext) ? ext : "tsx"
      end

      def compiled_template_source(template, source)
        if template.identifier.end_with?(".erb")
          erb_handler.call(template, source)
        else
          source.dump
        end
      end

      def erb_handler
        @erb_handler ||= ActionView::Template.registered_template_handler(:erb)
      end

      def partial_template?(template)
        File.basename(template.identifier).start_with?("_")
      end
    end
  end
end
