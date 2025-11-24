# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe 'Client-side Hydration', :js, type: :system do
  describe 'interactive component hydration' do
    it 'hydrates the component and makes it interactive' do
      visit '/interactive'

      # Wait for initial SSR content to load
      expect(page).to have_content('Interactive Counter', wait: 10)
      expect(page).to have_content('Count: 10', wait: 10)

      # Component should be present with data attributes for hydration
      expect(page).to have_css('[data-component="InteractiveCounter"]', wait: 10)
      expect(page).to have_css('[data-island-uuid]', wait: 10)

      # Wait for hydration to complete - wait for button to be interactive
      expect(page).to have_css('[data-testid="increment-btn"]', wait: 10)

      # Check browser console for errors - this is where hydration failures show up
      begin
        Timeout.timeout(5) do
          if page.driver.browser.respond_to?(:logs)
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
          end
        end
      rescue Timeout::Error
        # Log API might hang, continue with test
        puts 'Warning: Browser logs API timed out, continuing test'
      rescue StandardError => e
        # Ignore log retrieval errors
        puts "Warning: Could not retrieve browser logs: #{e.message}"
      end

      # Test interactivity - click increment button
      find('[data-testid="increment-btn"]', wait: 10).click

      # Count should update (this only works if hydration succeeded)
      expect(page).to have_content('Count: 11', wait: 10)

      # Click decrement button
      find('[data-testid="decrement-btn"]', wait: 10).click

      # Count should update again
      expect(page).to have_content('Count: 10', wait: 10)
    end

    it 'loads components through Vite dev server' do
      visit '/interactive'

      # Check that the boot script loads successfully
      expect(page).to have_css('script[src*="vite"]', visible: false, wait: 10)

      # Wait for script to load and execute - wait for button to appear
      expect(page).to have_css('[data-testid="increment-btn"]', wait: 10)

      # Check for JavaScript errors related to module loading
      begin
        Timeout.timeout(5) do
          if page.driver.browser.respond_to?(:logs)
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
      rescue Timeout::Error
        # Log API might hang, continue with test
        puts 'Warning: Browser logs API timed out, continuing test'
      rescue StandardError => e
        # Ignore log retrieval errors
        puts "Warning: Could not retrieve browser logs: #{e.message}"
      end
    end

    it 'hydrates a TSX page without importing React globally' do
      visit '/pages/auto_runtime'

      expect(page).to have_css('[data-testid="auto-runtime-page"]', wait: 10)
      expect(page).to have_content('Hydration Playground', wait: 10)
      expect(page).to have_content('Count: 16', wait: 10)

      begin
        Timeout.timeout(5) do
          if page.driver.browser.respond_to?(:logs)
            logs = page.driver.browser.logs.get(:browser)
            reference_errors = logs.select do |log|
              log.level == 'SEVERE' && log.message.include?('React is not defined')
            end

            expect(reference_errors).to be_empty,
                                       "Expected no 'React is not defined' errors, but found:\n#{reference_errors.map(&:message).join("\n")}"
          end
        end
      rescue Timeout::Error
        puts 'Warning: Browser logs API timed out, continuing test'
      rescue StandardError => e
        puts "Warning: Could not retrieve browser logs: #{e.message}"
      end

      find('[data-testid="auto-runtime-increment"]', wait: 10).click
      expect(page).to have_content('Count: 17', wait: 10)
    end
  end
end
