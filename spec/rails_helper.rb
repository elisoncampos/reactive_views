# frozen_string_literal: true

# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'

# Load the Rails application (spec/dummy)
require_relative 'dummy/config/environment'

# Prevent database truncation if the environment is production
abort('The Rails environment is running in production mode!') if Rails.env.production?

# Require the gem code
require 'reactive_views'

require 'rspec/rails'
require 'capybara/rails'
require 'capybara/rspec'

# Add additional requires below this line. Rails is not loaded until this point!

# Requires supporting ruby files with custom matchers and macros, etc, in
# spec/support/ and its subdirectories.
Dir[File.join(__dir__, 'support', '**', '*.rb')].sort.each { |f| require f }

# Checks for pending migrations and applies them before tests are run.
# If you are not using ActiveRecord, you can remove this line.
# ActiveRecord::Migration.maintain_test_schema!

start_test_servers = ENV['REACTIVE_VIEWS_SKIP_SERVERS'] != '1'

RSpec.configure do |config|
  if start_test_servers
    config.before(:suite) { TestServers.start }
    config.after(:suite) { TestServers.stop }
  end

  # Configure ReactiveViews for testing
  config.before do
    ReactiveViews.configure do |rv_config|
      rv_config.enabled = true
      rv_config.ssr_url = "http://localhost:#{TestServers::SSR_PORT}"
      rv_config.component_views_paths = [ "#{TestServers::SPEC_DUMMY_DIR}/app/views/components" ]
    end
  end

  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  # config.fixture_path = Rails.root.join('spec/fixtures')

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = true

  # You can uncomment this line to turn off ActiveRecord support entirely.
  config.use_active_record = false

  # RSpec Rails can automatically mix in different behaviours to your tests
  # based on their file location, for example enabling you to call `get` and
  # `post` in specs under `spec/controllers`.
  #
  # You can disable this behaviour by removing the line below, and instead
  # explicitly tag your specs with their type, e.g.:
  #
  #     RSpec.describe UsersController, type: :controller do
  #       # ...
  #     end
  #
  # The different available types are documented in the features, such as in
  # https://rspec.info/features/6-0/rspec-rails
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")

  # Configure Capybara host
  config.before(:each, type: :system) do
    driven_by :cuprite
    host! 'http://127.0.0.1:3000'
  end

  # Clear renderer cache and give SSR server breathing room between system tests
  config.before(:each, type: :system, js: true) do
    ReactiveViews::Renderer.clear_cache if ReactiveViews::Renderer.respond_to?(:clear_cache)
    sleep 0.25 # Pause to let SSR server recover between tests
  end
end
