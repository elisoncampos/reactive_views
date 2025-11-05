# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe 'Counter Component with useState', type: :system, js: true do
  VITE_PORT = 5174 unless defined?(VITE_PORT)
  SSR_PORT = 5175 unless defined?(SSR_PORT)
  SPEC_INTERNAL_DIR = File.expand_path('../internal', __dir__) unless defined?(SPEC_INTERNAL_DIR)

  before(:all) do
    # In CI, servers are started by the workflow, so we just verify they're running
    # In local development, start servers if they're not already running
    if ENV['CI']
      # Just wait for servers to be ready (they're already started by CI)
      wait_for_server("http://localhost:#{VITE_PORT}", timeout: 15)
      wait_for_server("http://localhost:#{SSR_PORT}", timeout: 15)
      @vite_pid = nil
      @ssr_pid = nil
    else
      # Local development: kill any processes using our ports to avoid conflicts
      [VITE_PORT, SSR_PORT, 3000, 3036].each do |port|
        system("lsof -ti:#{port} | xargs kill -9 2>/dev/null", out: File::NULL, err: File::NULL)
      end
      sleep 1

      # Start Vite dev server (use test-specific config to avoid RubyPlugin conflicts)
      @vite_pid = spawn(
        { 'RV_VITE_PORT' => VITE_PORT.to_s },
        'npx vite --config vite.test.config.ts',
        chdir: SPEC_INTERNAL_DIR,
        out: File::NULL,
        err: File::NULL
      )

      # Start SSR server
      gem_root = Gem.loaded_specs['reactive_views']&.gem_dir || File.expand_path('../..', __dir__)
      ssr_script = File.join(gem_root, 'node', 'ssr', 'server.mjs')
      @ssr_pid = spawn(
        { 'RV_SSR_PORT' => SSR_PORT.to_s, 'PROJECT_ROOT' => SPEC_INTERNAL_DIR },
        'node', ssr_script,
        out: File::NULL,
        err: File::NULL
      )

      # Wait for servers to be ready
      wait_for_server("http://localhost:#{VITE_PORT}", timeout: 15)
      wait_for_server("http://localhost:#{SSR_PORT}", timeout: 15)
    end
  end

  after(:all) do
    # Only kill servers if we started them (not in CI)
    unless ENV['CI']
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
    end
  end

  before do
    ReactiveViews.configure do |config|
      config.enabled = true
      config.ssr_url = "http://localhost:#{SSR_PORT}"
      config.component_views_paths = ["#{SPEC_INTERNAL_DIR}/app/views/components"]
    end
  end

  describe 'useState hook functionality' do
    it 'renders counter with initial count and allows state updates' do
      visit '/counter'

      # Wait for initial SSR content to load
      expect(page).to have_content('Counter Component', wait: 10)
      expect(page).to have_content('Count: 5', wait: 10)

      # Component should be present with data attributes for hydration
      expect(page).to have_css('[data-component="Counter"]', wait: 10)
      expect(page).to have_css('[data-island-uuid]', wait: 10)

      # Wait for hydration to complete - wait for button to be interactive
      expect(page).to have_css('[data-testid="increment-btn"]', wait: 10)

      # Check for JavaScript errors with timeout
      begin
        Timeout.timeout(5) do
          logs = page.driver.browser.logs.get(:browser)
          errors = logs.select { |log| log.level == 'SEVERE' && !log.message.include?('favicon.ico') }
          expect(errors).to be_empty,
                            "Expected no JavaScript errors, but found:\n#{errors.map(&:message).join("\n")}"
        end
      rescue Timeout::Error
        # Log API might hang, continue with test
        puts "Warning: Browser logs API timed out, continuing test"
      rescue StandardError => e
        # Ignore log retrieval errors
        puts "Warning: Could not retrieve browser logs: #{e.message}"
      end

      # Test useState - increment button
      find('[data-testid="increment-btn"]', wait: 10).click
      expect(page).to have_content('Count: 6', wait: 10)

      # Click again
      find('[data-testid="increment-btn"]', wait: 10).click
      expect(page).to have_content('Count: 7', wait: 10)

      # Test decrement
      find('[data-testid="decrement-btn"]', wait: 10).click
      expect(page).to have_content('Count: 6', wait: 10)

      # Test reset
      find('[data-testid="reset-btn"]', wait: 10).click
      expect(page).to have_content('Count: 5', wait: 10)
    end
  end

  private

  def wait_for_server(url, timeout: 10)
    require 'net/http'
    require 'uri'

    start_time = Time.now
    loop do
      begin
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 2
        http.read_timeout = 2
        response = http.get(uri.request_uri)
        break if response.code.to_i < 500
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError
        # Server not ready yet - these are expected while waiting
      rescue StandardError => e
        # Other errors - log but continue waiting
        puts "Warning: Error checking server #{url}: #{e.class} - #{e.message}" if ENV['CI']
      end

      raise "Server at #{url} did not start within #{timeout} seconds" if Time.now - start_time > timeout

      sleep 0.5
    end
  end
end
