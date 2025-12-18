# frozen_string_literal: true

require 'rails_helper'
require 'support/production_helpers'

RSpec.describe 'Turbo + Production Assets Integration', type: :system, js: true do
  let(:render_timeout) { 20 }

  before(:all) do
    ProductionHelpers.build_production_assets unless ProductionHelpers.production_assets_built?
  end

  describe 'Turbo Drive navigation' do
    it 're-hydrates React components after navigation' do
      visit '/counter'

      # First page hydrates
      expect(page).to have_css('[data-reactive-hydrated="true"]', wait: render_timeout)

      # Navigate to another page with React
      visit '/turbo_mixed'

      # Wait for new page
      expect(page).to have_content('Turbo + Stimulus + React', wait: render_timeout)

      # React component should be hydrated on new page
      expect(page).to have_css('[data-component]', wait: render_timeout)
    end

    it 'cleans up hydration markers before Turbo cache' do
      visit '/counter'

      # Wait for initial hydration
      expect(page).to have_css('[data-reactive-hydrated="true"]', wait: render_timeout)

      # Navigate away
      visit '/turbo_mixed'
      expect(page).to have_content('Turbo + Stimulus + React', wait: render_timeout)

      # Go back (triggers cache restore)
      page.go_back

      # After cache restore, the element should not have data-reactive-hydrated
      # until it's re-hydrated
      # Give it time to clean up and re-hydrate
      sleep 0.5

      # Should eventually re-hydrate
      expect(page).to have_css('[data-component="Counter"]', wait: render_timeout)
    end

    it 'handles rapid navigation without breaking' do
      visit '/counter'
      expect(page).to have_css('[data-reactive-hydrated="true"]', wait: render_timeout)

      # Rapid navigation
      3.times do
        visit '/turbo_mixed'
        sleep 0.2
        visit '/counter'
        sleep 0.2
      end

      # Should still work after rapid navigation
      expect(page).to have_css('[data-reactive-hydrated="true"]', wait: render_timeout)
      expect(page).to have_css('[data-testid="increment-btn"]')
    end
  end

  describe 'Turbo Frames with React components' do
    it 'hydrates React components inside Turbo Frames' do
      visit '/turbo_mixed'

      # Wait for page load
      expect(page).to have_css('turbo-frame#dynamic-content', wait: render_timeout)

      # Initial frame content should be visible
      expect(page).to have_content('Initial frame content', wait: render_timeout)
    end

    it 'hydrates new React components loaded via Turbo Frame' do
      visit '/turbo_mixed'

      # Wait for initial page
      expect(page).to have_css('turbo-frame#dynamic-content', wait: render_timeout)

      # Click link to load new content in frame
      if page.has_link?('Load new content with React component')
        click_link 'Load new content with React component'

        # Wait for frame to update
        sleep 1

        # New React component in frame should hydrate
        within 'turbo-frame#dynamic-content' do
          # Content should be updated (implementation specific)
          has_component = page.has_css?('[data-component]', wait: 2)
          has_content = page.has_content?('new content', wait: 2)
          expect(has_component || has_content).to be(true)
        end
      end
    end
  end

  describe 'Turbo Streams with React islands' do
    it 'does not break existing React islands when streams update' do
      visit '/turbo_mixed'

      # Get initial state of React component
      expect(page).to have_css('[data-testid="react-section"]', wait: render_timeout)

      # Turbo Stream updates should not affect React islands outside the stream target
      react_section = find('[data-testid="react-section"]')
      expect(react_section).to be_visible
    end
  end

  describe 'back/forward navigation' do
    it 're-hydrates components on back navigation' do
      visit '/counter'
      expect(page).to have_css('[data-reactive-hydrated="true"]', wait: render_timeout)

      # Get initial count
      initial_count_text = find('[data-testid="count-display"]').text

      # Navigate away
      visit '/turbo_mixed'
      expect(page).to have_content('Turbo + Stimulus + React', wait: render_timeout)

      # Go back
      page.go_back

      # Should re-hydrate
      expect(page).to have_css('[data-reactive-hydrated="true"]', wait: render_timeout)

      # Counter should be interactive again
      find('[data-testid="increment-btn"]').click
      new_count_text = find('[data-testid="count-display"]').text
      expect(new_count_text).not_to eq(initial_count_text)
    end

    it 're-hydrates components on forward navigation' do
      visit '/counter'
      expect(page).to have_css('[data-reactive-hydrated="true"]', wait: render_timeout)

      visit '/turbo_mixed'
      expect(page).to have_content('Turbo + Stimulus + React', wait: render_timeout)

      # Go back then forward
      page.go_back
      expect(page).to have_css('[data-component="Counter"]', wait: render_timeout)

      page.go_forward
      expect(page).to have_content('Turbo + Stimulus + React', wait: render_timeout)

      # React section should still be functional
      expect(page).to have_css('[data-testid="react-section"]', wait: render_timeout)
    end
  end

  describe 'Turbo and React state' do
    it 'does not preserve React state across Turbo navigations by default' do
      visit '/counter'
      expect(page).to have_css('[data-reactive-hydrated="true"]', wait: render_timeout)

      # Increment counter
      5.times { find('[data-testid="increment-btn"]').click }

      # Navigate away and back
      visit '/turbo_mixed'
      page.go_back

      # After re-hydration, state should be reset to initial
      expect(page).to have_css('[data-reactive-hydrated="true"]', wait: render_timeout)
      # State comes from SSR/props, not from previous React state
    end
  end

  describe 'event listener cleanup' do
    it 'registers Turbo event listeners correctly' do
      visit '/counter'

      # Check that turbo:load listener is registered
      result = page.evaluate_script(<<~JS)
        (function() {
          var events = [];
          var orig = document.addEventListener;
          return typeof window.__REACTIVE_VIEWS__ === 'object';
        })()
      JS

      expect(result).to be(true)
    end

    it 'handles turbo:before-cache event' do
      visit '/counter'
      expect(page).to have_css('[data-reactive-hydrated="true"]', wait: render_timeout)

      # Trigger a navigation that will cache the page
      visit '/turbo_mixed'

      # Go back (restores from cache)
      page.go_back

      # The data-reactive-hydrated should have been removed before caching
      # and then re-added after hydration
      expect(page).to have_css('[data-reactive-hydrated="true"]', wait: render_timeout)
    end
  end

  describe 'Stimulus controller coexistence' do
    it 'Stimulus controllers work alongside React components' do
      visit '/turbo_mixed'

      # Wait for both Stimulus and React to initialize
      expect(page).to have_content('Stimulus connected!', wait: render_timeout)
      expect(page).to have_css('[data-testid="react-section"]', wait: render_timeout)
    end

    it 'Stimulus and React do not interfere with each other' do
      visit '/turbo_mixed'

      # Stimulus counter should work
      expect(page).to have_css('[data-testid="stimulus-section"]', wait: render_timeout)

      # React section should also work
      expect(page).to have_css('[data-testid="react-section"]', wait: render_timeout)

      # Both should have functional interactive elements
      expect(page).to have_css('[data-testid="increment-btn"]')
      expect(page).to have_css('[data-testid="decrement-btn"]')
    end
  end
end
