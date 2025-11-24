# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe 'Full Page Hooks', type: :system, js: true do
  def log_browser_console
    return unless page.driver.browser.respond_to?(:logs)

    logs = page.driver.browser.logs.get(:browser)
    filtered = logs.reject { |log| log.message.include?('favicon.ico') }
    return if filtered.empty?

    puts "\n[FullPageHooksSpec] Browser console logs:\n"
    filtered.each { |log| puts "#{log.level}: #{log.message}" }
  rescue StandardError => e
    puts "[FullPageHooksSpec] Unable to read browser logs: #{e.message}"
  end

  shared_examples 'full page hydration works' do |path:, page_test_id:, initial_count:|
    it "hydrates #{page_test_id} and enables hooks" do
      visit path
      expect(page).to have_css("[data-testid='#{page_test_id}']", wait: 10)
      expect(page).to have_css('[data-reactive-page="true"][data-reactive-hydrated="true"]', wait: 10)
      expect(page).to have_content("Count: #{initial_count}", wait: 10)
      expect(page).to have_content('Effect: hydrated', wait: 10)

      find('[data-testid="page-increment"]').click
      expect(page).to have_content("Count: #{initial_count + 1}", wait: 5)

      find('[data-testid="page-reset"]').click
      expect(page).to have_content("Count: #{initial_count}", wait: 5)

      log_browser_console
    end
  end

  include_examples 'full page hydration works',
                   path: '/pages/full_page_tsx',
                   page_test_id: 'full-page-tsx',
                   initial_count: 7

  include_examples 'full page hydration works',
                   path: '/pages/full_page_jsx',
                   page_test_id: 'full-page-jsx',
                   initial_count: 4
end
