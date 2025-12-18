# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe 'Counter Component with useState', type: :system, js: true do
  describe 'useState hook functionality' do
    it 'renders counter with initial count and allows state updates' do
      visit '/counter'

      # Wait for initial SSR content to load
      expect(page).to have_content('Counter Component', wait: 10)
      expect(page).to have_content('Count: 5', wait: 10)

      # Component should be present with data attributes for hydration
      expect(page).to have_css('[data-component="Counter"]', wait: 10)
      expect(page).to have_css('[data-island-uuid]', wait: 10)

      # Wait for hydration to complete
      expect(page).to have_css('[data-reactive-hydrated="true"]', wait: 10)

      # Wait for button to be interactive
      expect(page).to have_css('[data-testid="increment-btn"]', wait: 10)

      # Check for JavaScript errors with timeout
      begin
        Timeout.timeout(5) do
          if page.driver.browser.respond_to?(:logs)
            logs = page.driver.browser.logs.get(:browser)
            errors = logs.select { |log| log.level == 'SEVERE' && !log.message.include?('favicon.ico') }
            expect(errors).to be_empty,
                              "Expected no JavaScript errors, but found:\n#{errors.map(&:message).join("\n")}"
          end
        end
      rescue Timeout::Error
        # Log API might hang, continue with test
        puts 'Warning: Browser logs API timed out, continuing test'
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
end
