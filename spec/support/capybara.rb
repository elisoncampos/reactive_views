# frozen_string_literal: true

require 'capybara/rspec'
require 'selenium-webdriver'

# Configure Capybara
Capybara.configure do |config|
  # Increase timeout for slow CI environments
  config.default_max_wait_time = ENV.fetch('CAPYBARA_TIMEOUT', 10).to_i
  config.default_driver = :rack_test
  config.javascript_driver = :headless_chrome
  config.server = :puma, { Silent: true }
  config.server_host = '127.0.0.1'
  config.server_port = 3000
end

# Configure Selenium with headless Chrome
Capybara.register_driver :headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless=new')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--disable-gpu')
  options.add_argument('--window-size=1400,1400')
  options.add_argument('--disable-software-rasterizer')
  options.add_argument('--disable-extensions')
  options.add_argument('--disable-background-timer-throttling')
  options.add_argument('--disable-backgrounding-occluded-windows')
  options.add_argument('--disable-renderer-backgrounding')
  options.add_argument('--disable-features=TranslateUI')
  options.add_argument('--disable-ipc-flooding-protection')

  # Set page load timeout
  options.page_load_strategy = :normal

  # Enable browser console logs
  options.logging_prefs = { browser: 'ALL' }

  driver = Capybara::Selenium::Driver.new(
    app,
    browser: :chrome,
    options: options,
    timeout: ENV.fetch('CAPYBARA_TIMEOUT', 10).to_i
  )

  # Set explicit timeouts
  driver.browser.manage.timeouts.implicit_wait = ENV.fetch('CAPYBARA_TIMEOUT', 10).to_i
  driver.browser.manage.timeouts.page_load = 30
  driver.browser.manage.timeouts.script_timeout = 30

  driver
end

# Use headless Chrome for JavaScript tests
Capybara.javascript_driver = :headless_chrome

RSpec.configure do |config|
  # Configure Capybara for system specs
  config.before(:each, type: :system) do
    driven_by :headless_chrome
  end

  # Force cleanup of all Chrome processes after suite
  config.after(:suite) do
    # Kill any remaining Chrome processes (in CI only)
    if ENV['CI']
      system('pkill -9 chrome 2>/dev/null', out: File::NULL, err: File::NULL)
      system('pkill -9 chromedriver 2>/dev/null', out: File::NULL, err: File::NULL)
    end
  end
end
