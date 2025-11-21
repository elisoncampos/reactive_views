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

    CLEANUP_INTERVAL = 300 # seconds
    DEFAULT_MAX_AGE = 1800 # seconds

    class << self
      def write(content, identifier:, extension: "tsx")
        prune_if_needed

        temp_dir = temp_root
        FileUtils.mkdir_p(temp_dir)

        timestamp = Time.now.to_i
        random = SecureRandom.hex(8)
        safe_identifier = (identifier || "reactive_views").to_s.gsub(/[^a-zA-Z0-9_-]/, "_")
        resolved_extension = (extension || default_extension_for(identifier))

        temp_path = File.join(temp_dir, "#{safe_identifier}_#{timestamp}_#{random}.#{resolved_extension}")
        File.write(temp_path, content)

        TempFile.new(temp_path)
      end

      def prune(max_age_seconds: DEFAULT_MAX_AGE)
        prune_stale_files(max_age_seconds: max_age_seconds)
      end

      private

      def temp_root
        if defined?(Rails)
          Rails.root.join("tmp", "reactive_views_full_page").to_s
        else
          File.join(Dir.tmpdir, "reactive_views_full_page")
        end
      end

      def default_extension_for(identifier)
        identifier.to_s.end_with?(".jsx", ".jsx.erb") ? "jsx" : "tsx"
      end

      def prune_if_needed
        return unless cleanup_due?

        prune_stale_files(max_age_seconds: DEFAULT_MAX_AGE)
      ensure
        @last_prune_at = Time.now
      end

      def cleanup_due?
        return true unless defined?(@last_prune_at) && @last_prune_at

        Time.now - @last_prune_at > CLEANUP_INTERVAL
      end

      def prune_stale_files(max_age_seconds:)
        cutoff = Time.now - max_age_seconds
        Dir.glob(File.join(temp_root, "*")).each do |path|
          next unless File.file?(path)
          next unless File.mtime(path) < cutoff

          File.delete(path)
        rescue StandardError
          next
        end
      end
    end
  end
end
