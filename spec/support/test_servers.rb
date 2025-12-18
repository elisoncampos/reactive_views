# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module TestServers
  VITE_PORT = 5174
  SSR_PORT = 5175
  SPEC_DUMMY_DIR = File.expand_path('../dummy', __dir__)
  VITE_TEST_BASE = "/vite-test"
  HOST = "127.0.0.1"

  class << self
    attr_reader :vite_pid, :ssr_pid

    def start
      return if ENV['REACTIVE_VIEWS_SKIP_SERVERS'] == '1'

      puts 'Starting test servers...'

      # In CI we should not rely on the workflow to start servers, and we also
      # shouldn't run `lsof | kill -9` (can be unavailable / too aggressive).
      #
      # Instead: if a server is already up, reuse it; otherwise spawn it.
      unless ENV['CI']
        # Kill any processes using our ports to avoid conflicts
        [ VITE_PORT, SSR_PORT ].each do |port|
          system("lsof -ti:#{port} | xargs kill -9 2>/dev/null", out: File::NULL, err: File::NULL)
        end
        sleep 1
      end

      # Start Vite dev server
      unless server_up?("http://#{HOST}:#{VITE_PORT}#{VITE_TEST_BASE}/@vite/client")
        @vite_pid = spawn(
          { 'RV_VITE_PORT' => VITE_PORT.to_s },
          'npm exec -- vite --config vite.test.config.ts',
          chdir: SPEC_DUMMY_DIR,
          out: ENV['CI'] ? $stdout : File::NULL,
          err: ENV['CI'] ? $stderr : File::NULL
        )
      end

      # Start SSR server
      gem_root = File.expand_path('../../', __dir__)
      ssr_script = File.join(gem_root, 'node', 'ssr', 'server.mjs')

      # IMPORTANT: Run node in the gem root so it finds node_modules correctly
      unless server_up?("http://#{HOST}:#{SSR_PORT}/health")
        @ssr_pid = spawn(
          { 'RV_SSR_PORT' => SSR_PORT.to_s, 'PROJECT_ROOT' => SPEC_DUMMY_DIR },
          'node', ssr_script,
          chdir: gem_root, # Run from gem root where node_modules are
          out: ENV['CI'] ? $stdout : File::NULL,
          err: ENV['CI'] ? $stderr : File::NULL
        )
      end

      wait_for_server("http://#{HOST}:#{VITE_PORT}#{VITE_TEST_BASE}/@vite/client")
      wait_for_server("http://#{HOST}:#{SSR_PORT}/health")
      puts 'Test servers started.'
    end

    def stop
      return if ENV['CI'] || ENV['REACTIVE_VIEWS_SKIP_SERVERS'] == '1'

      puts 'Stopping test servers...'
      Process.kill('TERM', @vite_pid) if @vite_pid
      Process.kill('TERM', @ssr_pid) if @ssr_pid

      begin
        Process.wait(@vite_pid) if @vite_pid
      rescue StandardError
        nil
      end

      begin
        Process.wait(@ssr_pid) if @ssr_pid
      rescue StandardError
        nil
      end
      puts 'Test servers stopped.'
    end

    def clear_ssr_cache
      uri = URI.parse("http://localhost:#{SSR_PORT}/clear-cache")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 5
      http.read_timeout = 5

      request = Net::HTTP::Post.new(uri.request_uri)
      http.request(request)
    rescue StandardError
      # Ignore errors - server might not support this endpoint
    end

    private

    def server_up?(url)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 0.5
      http.read_timeout = 0.5
      res = http.get(uri.request_uri)
      res.code.to_i.positive? && res.code.to_i < 500
    rescue StandardError
      false
    end

    def wait_for_server(url, timeout: 30)
      start_time = Time.now
      loop do
        begin
          uri = URI.parse(url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.open_timeout = 1
          http.read_timeout = 1
          response = http.get(uri.request_uri)
          break if response.code.to_i < 500
        rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError
          # Server not ready yet
        rescue StandardError
          # Ignore other errors
        end

        if Time.now - start_time > timeout
          raise "Server at #{url} did not start within #{timeout} seconds"
        end

        sleep 0.5
      end

      # Warm up the SSR server by pre-compiling commonly used components
      warmup_ssr("http://#{HOST}:#{SSR_PORT}") if url.include?(SSR_PORT.to_s)
    end

    def warmup_ssr(ssr_url)
      # Pre-compile components to warm up the bundler cache
      # This prevents timeout issues during tests
      warmup_components = %w[
        Counter.tsx
        InteractiveCounter.tsx
        HooksPlayground.tsx
        HooksPlaygroundJsx.jsx
        ShadcnDemo.tsx
      ]

      puts "  Warming up SSR server with #{warmup_components.length} components..."

      warmup_components.each do |component|
        component_path = File.join(SPEC_DUMMY_DIR, 'app', 'views', 'components', component)
        next unless File.exist?(component_path)

        begin
          uri = URI.parse("#{ssr_url}/render")
          http = Net::HTTP.new(uri.host, uri.port)
          http.open_timeout = 30
          http.read_timeout = 30

          request = Net::HTTP::Post.new(uri.request_uri)
          request['Content-Type'] = 'application/json'
          request.body = JSON.generate({ componentPath: component_path, props: {} })

          response = http.request(request)
          status = response.code.to_i < 400 ? '✓' : '✗'
          puts "    #{status} #{component}"
        rescue StandardError => e
          puts "    ✗ #{component} (#{e.message})"
        end
      end

      # Additional pause to let esbuild finish any pending work
      sleep 1
      puts "  SSR warmup complete."
    end
  end
end
