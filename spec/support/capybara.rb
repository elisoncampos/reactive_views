# frozen_string_literal: true

require "capybara/rspec"
require "selenium-webdriver"

# Configure Capybara
Capybara.configure do |config|
  config.default_max_wait_time = 5
  config.server = :puma, { Silent: true }
  config.server_host = "127.0.0.1"
  config.server_port = 3000
end

# Configure Selenium with headless Chrome
Capybara.register_driver :headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--no-sandbox")
  options.add_argument("--disable-dev-shm-usage")
  options.add_argument("--disable-gpu")
  options.add_argument("--window-size=1400,1400")

  # Enable browser console logs
  options.logging_prefs = { browser: "ALL" }

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

# Use headless Chrome for JavaScript tests
Capybara.javascript_driver = :headless_chrome

RSpec.configure do |config|
  # Configure Capybara for system specs
  config.before(:each, type: :system) do
    driven_by :headless_chrome
  end
end
