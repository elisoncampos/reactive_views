# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Client-side Hydration', type: :system, js: true do
  VITE_PORT = 5174 unless defined?(VITE_PORT)
  SSR_PORT = 5175 unless defined?(SSR_PORT)
  SPEC_INTERNAL_DIR = File.expand_path('../internal', __dir__) unless defined?(SPEC_INTERNAL_DIR)

  before(:all) do
    # Kill any processes using our ports to avoid conflicts
    [VITE_PORT, SSR_PORT, 3000, 3036].each do |port|
      system("lsof -ti:#{port} | xargs kill -9 2>/dev/null", out: File::NULL, err: File::NULL)
    end
    sleep 1 # Give OS time to release ports

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
    wait_for_server("http://localhost:#{SSR_PORT}", timeout: 15) # SSR server root endpoint
  end

  after(:all) do
    # Kill Vite and SSR servers
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

  before do
    # Configure ReactiveViews for testing
    ReactiveViews.configure do |config|
      config.enabled = true
      config.ssr_url = "http://localhost:#{SSR_PORT}"
      config.component_views_paths = ["#{SPEC_INTERNAL_DIR}/app/views/components"]
    end
  end

  describe 'interactive component hydration' do
    it 'hydrates the component and makes it interactive' do
      visit '/interactive'

      # Wait for initial SSR content to load
      expect(page).to have_content('Interactive Counter')
      expect(page).to have_content('Count: 10')

      # Component should be present with data attributes for hydration
      expect(page).to have_css('[data-component="InteractiveCounter"]')
      expect(page).to have_css('[data-island-uuid]')

      # Wait for hydration to complete (give it some time)
      sleep 5

      # Check browser console for errors - this is where hydration failures show up
      logs = page.driver.browser.logs.get(:browser)
      hydration_errors = logs.select do |log|
        (log.message.include?('Failed to hydrate') ||
         log.message.include?('404') ||
         log.message.include?('Component not found')) &&
          !log.message.include?('favicon.ico') # Ignore favicon 404s
      end

      # This should FAIL with current code - we expect hydration to work with no errors
      expect(hydration_errors).to be_empty,
                                  "Expected no hydration errors, but found:\n#{hydration_errors.map(&:message).join("\n")}"

      # Test interactivity - click increment button
      find('[data-testid="increment-btn"]').click

      # Count should update (this only works if hydration succeeded)
      expect(page).to have_content('Count: 11')

      # Click decrement button
      find('[data-testid="decrement-btn"]').click

      # Count should update again
      expect(page).to have_content('Count: 10')
    end

    it 'loads components through Vite dev server' do
      visit '/interactive'

      # Check that the boot script loads successfully
      expect(page).to have_css('script[src*="vite"]', visible: false)

      # Give time for script to load and execute
      sleep 2

      # Check for JavaScript errors related to module loading
      logs = page.driver.browser.logs.get(:browser)
      module_errors = logs.select do |log|
        log.level == 'SEVERE' && (
          log.message.include?('Failed to load module') ||
          log.message.include?('404') ||
          log.message.include?('Cannot find module')
        ) && !log.message.include?('favicon.ico') # Ignore favicon 404s
      end

      expect(module_errors).to be_empty,
                               "Expected modules to load successfully, but found errors:\n#{module_errors.map(&:message).join("\n")}"
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
        response = Net::HTTP.get_response(uri)
        break if response.code.to_i < 500
      rescue StandardError
        # Server not ready yet
      end

      raise "Server at #{url} did not start within #{timeout} seconds" if Time.now - start_time > timeout

      sleep 0.5
    end
  end
end
