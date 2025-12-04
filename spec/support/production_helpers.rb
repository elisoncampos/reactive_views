# frozen_string_literal: true

require 'json'
require 'fileutils'

# Helper methods for production environment tests
module ProductionHelpers
  DUMMY_APP_PATH = File.expand_path('../dummy', __dir__)
  VITE_OUTPUT_PATH = File.join(DUMMY_APP_PATH, 'public', 'vite')
  MANIFEST_PATH = File.join(VITE_OUTPUT_PATH, '.vite', 'manifest.json')
  ALTERNATE_MANIFEST_PATH = File.join(VITE_OUTPUT_PATH, 'manifest.json')

  class << self
    # Build production assets for the dummy app
    # @param clean [Boolean] Whether to clean output directory first
    # @return [Boolean] True if build succeeded
    def build_production_assets(clean: true)
      if clean
        FileUtils.rm_rf(VITE_OUTPUT_PATH)
        FileUtils.mkdir_p(VITE_OUTPUT_PATH)
      end

      Dir.chdir(DUMMY_APP_PATH) do
        system(
          { 'NODE_ENV' => 'production', 'RAILS_ENV' => 'production' },
          'npx vite build --config vite.config.ts',
          out: File::NULL,
          err: File::NULL
        )
      end
    end

    # Check if production assets have been built
    # @return [Boolean] True if manifest exists
    def production_assets_built?
      File.exist?(MANIFEST_PATH) || File.exist?(ALTERNATE_MANIFEST_PATH)
    end

    # Load the Vite manifest
    # @return [Hash] The parsed manifest, or empty hash if not found
    def load_manifest
      path = File.exist?(MANIFEST_PATH) ? MANIFEST_PATH : ALTERNATE_MANIFEST_PATH
      return {} unless File.exist?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      {}
    end

    # Get the list of built asset files
    # @return [Array<String>] List of file paths relative to vite output
    def built_asset_files
      return [] unless Dir.exist?(VITE_OUTPUT_PATH)

      Dir.glob(File.join(VITE_OUTPUT_PATH, '**', '*'))
         .select { |f| File.file?(f) }
         .map { |f| f.sub("#{VITE_OUTPUT_PATH}/", '') }
    end

    # Get the total size of built assets in bytes
    # @return [Integer] Total size in bytes
    def total_asset_size
      built_asset_files.sum do |file|
        path = File.join(VITE_OUTPUT_PATH, file)
        File.exist?(path) ? File.size(path) : 0
      end
    end

    # Get asset sizes by type
    # @return [Hash<String, Integer>] Size in bytes by extension
    def asset_sizes_by_type
      sizes = Hash.new(0)
      built_asset_files.each do |file|
        ext = File.extname(file).downcase
        path = File.join(VITE_OUTPUT_PATH, file)
        sizes[ext] += File.size(path) if File.exist?(path)
      end
      sizes
    end

    # Check if a specific entry point exists in the manifest
    # @param entry_name [String] The entry point name
    # @return [Boolean]
    def entry_exists?(entry_name)
      manifest = load_manifest
      manifest.key?(entry_name) || manifest.key?("app/javascript/entrypoints/#{entry_name}")
    end

    # Get the hashed filename for an entry point
    # @param entry_name [String] The entry point name
    # @return [String, nil] The hashed filename or nil
    def hashed_filename(entry_name)
      manifest = load_manifest
      entry = manifest[entry_name] || manifest["app/javascript/entrypoints/#{entry_name}"]
      entry&.dig('file')
    end

    # Verify asset fingerprints are valid SHA hashes
    # @return [Array<Hash>] List of invalid fingerprints
    def validate_fingerprints
      invalid = []
      manifest = load_manifest

      manifest.each do |key, value|
        file = value['file']
        next unless file

        # Extract hash from filename (format: name-[hash].ext)
        if file =~ /-([a-f0-9]+)\.[^.]+$/
          hash = ::Regexp.last_match(1)
          # Vite uses 8-character hashes by default
          unless hash.match?(/^[a-f0-9]{8,}$/i)
            invalid << { entry: key, file: file, hash: hash, reason: 'Invalid hash format' }
          end
        else
          invalid << { entry: key, file: file, hash: nil, reason: 'No hash in filename' }
        end
      end

      invalid
    end

    # Start a production Rails server for testing
    # @param port [Integer] Port to run on
    # @return [Integer] PID of the server process
    def start_production_server(port: 3001)
      Dir.chdir(DUMMY_APP_PATH) do
        env = {
          'RAILS_ENV' => 'production',
          'SECRET_KEY_BASE' => 'test-secret-key-base-for-production-testing-only',
          'RAILS_SERVE_STATIC_FILES' => 'true',
          'RAILS_LOG_TO_STDOUT' => 'true'
        }

        pid = spawn(
          env,
          'bundle', 'exec', 'rails', 'server', '-p', port.to_s, '-b', '127.0.0.1',
          out: File::NULL,
          err: File::NULL
        )

        # Wait for server to be ready
        wait_for_server("http://127.0.0.1:#{port}/up", timeout: 30)

        pid
      end
    end

    # Stop a server by PID
    # @param pid [Integer] The process ID
    def stop_server(pid)
      return unless pid

      Process.kill('TERM', pid)
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      # Process already gone
    end

    # Wait for a server to become available
    # @param url [String] URL to check
    # @param timeout [Integer] Timeout in seconds
    def wait_for_server(url, timeout: 30)
      require 'net/http'

      start_time = Time.now
      uri = URI.parse(url)

      loop do
        begin
          http = Net::HTTP.new(uri.host, uri.port)
          http.open_timeout = 2
          http.read_timeout = 2
          response = http.get(uri.request_uri)
          break if response.code.to_i < 500
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Net::OpenTimeout, Net::ReadTimeout, SocketError
          # Server not ready yet
        end

        if Time.now - start_time > timeout
          raise "Server at #{url} did not become available within #{timeout} seconds"
        end

        sleep 0.5
      end
    end

    # Check if development-only code is present in built assets
    # @return [Array<Hash>] List of detected development code leaks
    def detect_development_code_leaks
      leaks = []

      built_asset_files.each do |file|
        next unless file.end_with?('.js')

        path = File.join(VITE_OUTPUT_PATH, file)
        content = File.read(path)

        # Check for React Refresh
        if content.include?('$RefreshReg$') || content.include?('@react-refresh')
          leaks << { file: file, type: 'react_refresh', message: 'React Refresh code found in production bundle' }
        end

        # Check for development-only React warnings
        if content.include?('__DEV__') && !content.include?('__DEV__:!1') && !content.include?('__DEV__:false')
          leaks << { file: file, type: 'dev_check', message: 'Development-only __DEV__ checks found' }
        end

        # Check for console.log statements (warning, not error)
        if content.match?(/console\.(log|debug|info)\s*\(/)
          leaks << { file: file, type: 'console_log', message: 'console.log statements found (consider removing)' }
        end

        # Check for sourceMappingURL pointing to dev server
        if content.include?('//# sourceMappingURL=http://localhost')
          leaks << { file: file, type: 'dev_sourcemap', message: 'Source map pointing to localhost' }
        end
      end

      leaks
    end

    # Measure asset loading performance metrics
    # @return [Hash] Performance metrics
    def measure_asset_metrics
      js_files = built_asset_files.select { |f| f.end_with?('.js') }
      css_files = built_asset_files.select { |f| f.end_with?('.css') }

      js_size = js_files.sum { |f| File.size(File.join(VITE_OUTPUT_PATH, f)) }
      css_size = css_files.sum { |f| File.size(File.join(VITE_OUTPUT_PATH, f)) }

      {
        total_js_size: js_size,
        total_css_size: css_size,
        total_size: js_size + css_size,
        js_file_count: js_files.size,
        css_file_count: css_files.size,
        total_file_count: built_asset_files.size,
        largest_js_file: js_files.max_by { |f| File.size(File.join(VITE_OUTPUT_PATH, f)) },
        largest_css_file: css_files.max_by { |f| File.size(File.join(VITE_OUTPUT_PATH, f)) }
      }
    end
  end
end

# RSpec configuration for production tests
RSpec.configure do |config|
  config.include ProductionHelpers

  # Tag for tests that require production assets
  config.before(:each, :requires_production_build) do
    unless ProductionHelpers.production_assets_built?
      skip 'Production assets not built. Run: cd spec/dummy && npx vite build'
    end
  end

  # Tag for tests that need a running production server
  config.around(:each, :production_server) do |example|
    @production_server_pid = ProductionHelpers.start_production_server
    example.run
  ensure
    ProductionHelpers.stop_server(@production_server_pid)
  end
end
