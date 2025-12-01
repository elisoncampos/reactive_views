# frozen_string_literal: true

require 'capybara/rspec'
require 'capybara/cuprite'

# Configure Capybara
Capybara.configure do |config|
  # Increase timeout for slow CI environments
  # Default to 15 seconds in CI, 10 locally
  default_timeout = ENV['CI'] ? 15 : 10
  config.default_max_wait_time = ENV.fetch('CAPYBARA_TIMEOUT', default_timeout).to_i
  config.default_driver = :rack_test
  config.javascript_driver = :cuprite
  config.server = :puma, { Silent: true }
  config.server_host = '127.0.0.1'
end

# Configure Cuprite
Capybara.register_driver :cuprite do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [ 1400, 1400 ],
    headless: true,
    process_timeout: 120,
    timeout: 120,
    browser_options: {
      'no-sandbox' => nil,
      'disable-gpu' => nil,
      'disable-dev-shm-usage' => nil
    },
    # Ignore pending connections to external services (like Vite)
    # This is crucial because the browser might be keeping connections open to Vite HMR/dev server
    pending_connection_errors: false
  )
end

RSpec.configure do |config|
  # Configure Capybara for system specs
  config.before(:each, type: :system) do
    driven_by :cuprite
  end

  # Reset browser state between tests to prevent pollution
  config.after(:each, type: :system) do
    # Clear all sessions to prevent test pollution
    begin
      Capybara.reset_sessions!
      page.driver.browser.reset if page.driver.respond_to?(:browser) && page.driver.browser.respond_to?(:reset)
    rescue StandardError
      # Ignore reset errors
    end
  end
end
