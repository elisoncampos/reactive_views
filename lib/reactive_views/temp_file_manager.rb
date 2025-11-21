# frozen_string_literal: true

require "fileutils"
require "securerandom"
require "tmpdir"

module ReactiveViews
  class TempFileManager
    TempFile = Struct.new(:path) do
      def delete
        File.delete(path) if path && File.exist?(path)
      end
    end

    class << self
      def write(content, identifier)
        temp_dir = if defined?(Rails)
                     Rails.root.join("tmp", "reactive_views_full_page")
        else
                     File.join(Dir.tmpdir, "reactive_views_full_page")
        end

        FileUtils.mkdir_p(temp_dir)

        # Generate unique filename
        timestamp = Time.now.to_i
        random = SecureRandom.hex(8)
        safe_identifier = identifier.gsub(/[^a-zA-Z0-9_-]/, "_")
        extension = if identifier.to_s.end_with?(".jsx", ".jsx.erb")
                      "jsx"
        else
                      "tsx"
        end

        # Check if it looks like JSX (heuristic) or if we want to support .jsx extension explicitly
        # For now we default to .tsx as it handles both usually (if types are valid)
        # But user requested proper jsx support.
        # The identifier might not have extension info.
        # We can try to guess or just use .tsx which esbuild handles for JSX too usually.

        temp_path = File.join(temp_dir, "#{safe_identifier}_#{timestamp}_#{random}.#{extension}")

        File.write(temp_path, content)
        TempFile.new(temp_path)
      end
    end
  end
end
