# frozen_string_literal: true

require "socket"
require "timeout"

module ReactiveViews
  # Manages the Node.js SSR server as a child process.
  # In production, the gem auto-spawns the SSR server on localhost,
  # eliminating the need for separate deployment configuration.
  class SsrProcess
    class ProcessError < StandardError; end

    HEALTH_CHECK_TIMEOUT = 10 # seconds to wait for server to become ready
    HEALTH_CHECK_INTERVAL = 0.1 # seconds between health check attempts

    class << self
      def ensure_running
        return if manually_configured?

        @mutex ||= Mutex.new
        @mutex.synchronize do
          return if running?

          start_server
        end
      end

      def running?
        return false unless @pid

        # Check if process is still alive
        Process.kill(0, @pid)
        true
      rescue Errno::ESRCH, Errno::EPERM
        @pid = nil
        false
      end

      def stop
        return unless @pid

        @mutex ||= Mutex.new
        @mutex.synchronize do
          return unless @pid

          begin
            Process.kill("TERM", @pid)
            # Give it a moment to shut down gracefully
            Timeout.timeout(5) do
              Process.wait(@pid)
            end
          rescue Errno::ESRCH, Errno::ECHILD
            # Process already dead
          rescue Timeout::Error
            # Force kill if it doesn't shut down gracefully
            begin
              Process.kill("KILL", @pid)
              Process.wait(@pid)
            rescue Errno::ESRCH, Errno::ECHILD
              # Process already dead
            end
          end

          @pid = nil
          log_info("SSR server stopped")
        end
      end

      def port
        @port
      end

      def url
        @port ? "http://127.0.0.1:#{@port}" : nil
      end

      private

      # Returns true if user has explicitly configured ssr_url via env or config
      # In that case, we don't auto-spawn - they're managing SSR externally
      def manually_configured?
        # Check if RV_SSR_URL or REACTIVE_VIEWS_SSR_URL is explicitly set
        return true if ENV.key?("RV_SSR_URL") || ENV.key?("REACTIVE_VIEWS_SSR_URL")

        # If the app (or test suite) explicitly configured ssr_url, respect it.
        # This is important for production specs, where we start SSR ourselves.
        configured = begin
          ReactiveViews.config&.ssr_url
        rescue StandardError
          nil
        end

        configured && !configured.to_s.empty?
      end

      def start_server
        @port = find_available_port
        ssr_script = find_ssr_script

        unless ssr_script
          raise ProcessError, "SSR server script not found. Ensure reactive_views gem is properly installed."
        end

        node_path = find_node_executable
        unless node_path
          raise ProcessError, "Node.js executable not found. Install Node.js to use SSR."
        end

        env = build_environment
        log_info("Starting SSR server on port #{@port}...")

        # Ensure log directory exists (Rails apps often don't commit /log)
        begin
          require "fileutils"
          FileUtils.mkdir_p(File.dirname(log_file_path))
        rescue StandardError
          # Best-effort; if it still fails, Process.spawn will raise with details.
        end

        # Spawn the Node process
        @pid = Process.spawn(
          env,
          node_path, ssr_script,
          in: :close,
          out: log_file_path,
          err: log_file_path,
          pgroup: true
        )

        # Register shutdown hook
        register_shutdown_hook

        # Wait for server to become ready
        wait_for_server

        # Update configuration to point to our managed server
        ReactiveViews.config.instance_variable_set(:@ssr_url, url)

        log_info("SSR server started (PID: #{@pid}, URL: #{url})")
      end

      def find_available_port
        # Use configured port if set
        if ENV["RV_SSR_PORT"]
          return ENV["RV_SSR_PORT"].to_i
        end

        # Find a random available port
        server = TCPServer.new("127.0.0.1", 0)
        port = server.addr[1]
        server.close
        port
      end

      def find_ssr_script
        # First check if we're in the gem directory (development)
        gem_root = if defined?(Bundler)
          spec = Bundler.load.specs.find { |s| s.name == "reactive_views" }
          spec&.gem_dir
        end

        # Fallback to Gem.loaded_specs
        gem_root ||= Gem.loaded_specs["reactive_views"]&.gem_dir

        # In development, check relative to this file
        gem_root ||= File.expand_path("../../..", __FILE__)

        ssr_script = File.join(gem_root, "node", "ssr", "server.mjs")
        File.exist?(ssr_script) ? ssr_script : nil
      end

      def find_node_executable
        # First try PATH
        node_in_path = `which node 2>/dev/null`.strip
        return node_in_path unless node_in_path.empty?

        # Common locations
        candidates = [
          File.expand_path("~/.asdf/shims/node"),
          File.expand_path("~/.nvm/current/bin/node"),
          "/opt/homebrew/bin/node",
          "/usr/local/bin/node",
          "/usr/bin/node",
          File.expand_path("~/.volta/bin/node")
        ]

        # Check NVM versions
        nvm_dir = ENV["NVM_DIR"] || File.expand_path("~/.nvm")
        if Dir.exist?(nvm_dir)
          nvm_node = Dir.glob("#{nvm_dir}/versions/node/*/bin/node").max
          candidates.unshift(nvm_node) if nvm_node
        end

        candidates.find { |path| path && File.executable?(path) }
      end

      def build_environment
        {
          "RV_SSR_PORT" => @port.to_s,
          "NODE_ENV" => rails_env,
          "PROJECT_ROOT" => project_root
        }
      end

      def rails_env
        if defined?(Rails)
          Rails.env.to_s
        else
          ENV.fetch("RAILS_ENV", "development")
        end
      end

      def project_root
        if defined?(Rails)
          Rails.root.to_s
        else
          Dir.pwd
        end
      end

      def log_file_path
        if defined?(Rails)
          Rails.root.join("log", "reactive_views_ssr.log").to_s
        else
          File.join(project_root, "log", "reactive_views_ssr.log")
        end
      end

      def wait_for_server
        require "net/http"

        deadline = Time.now + HEALTH_CHECK_TIMEOUT
        last_error = nil

        while Time.now < deadline
          begin
            uri = URI.parse("#{url}/health")
            http = Net::HTTP.new(uri.host, uri.port)
            http.open_timeout = 1
            http.read_timeout = 1

            response = http.get(uri.path)
            return if response.is_a?(Net::HTTPSuccess)

            last_error = "HTTP #{response.code}"
          rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Net::OpenTimeout, Net::ReadTimeout => e
            last_error = e.message
          end

          sleep HEALTH_CHECK_INTERVAL
        end

        # Server didn't start in time - kill it and raise
        stop
        raise ProcessError, "SSR server failed to start within #{HEALTH_CHECK_TIMEOUT}s: #{last_error}"
      end

      def register_shutdown_hook
        return if @shutdown_registered

        at_exit { SsrProcess.stop }
        @shutdown_registered = true
      end

      def log_info(message)
        if defined?(Rails) && Rails.logger
          Rails.logger.info("[ReactiveViews] #{message}")
        else
          $stdout.puts("[ReactiveViews] #{message}")
        end
      end
    end
  end
end
