# frozen_string_literal: true

require 'rails_helper'

# These tests verify that React components using shadcn/ui patterns (CVA variants,
# composition) work correctly with ReactiveViews SSR and hydration.
RSpec.describe 'shadcn/ui Component Compatibility', type: :system, js: true do
  # Longer timeout for SSR rendering
  let(:render_timeout) { 15 }

  describe 'class-variance-authority (CVA) integration' do
    it 'renders components using CVA variants and handles state updates' do
      visit '/shadcn_demo'

      # Wait for page to load
      expect(page).to have_content('shadcn/ui Component Test', wait: render_timeout)

      # Verify component rendered with correct content (use text selectors for resilience)
      expect(page).to have_content('shadcn/ui Integration Test', wait: render_timeout)
      expect(page).to have_button('Click me', wait: render_timeout)

      # Initial state
      expect(page).to have_content('Button clicked: 0 times', wait: render_timeout)
      expect(page).to have_content('Current variant: default', wait: render_timeout)

      # Wait for hydration and test interactivity
      click_button('Click me')
      expect(page).to have_content('Button clicked: 1 times', wait: render_timeout)

      # Click again
      click_button('Click me')
      expect(page).to have_content('Button clicked: 2 times', wait: render_timeout)

      # Test variant cycling (CVA functionality)
      click_button('Change variant')
      expect(page).to have_content('Current variant: destructive', wait: render_timeout)

      click_button('Change variant')
      expect(page).to have_content('Current variant: outline', wait: render_timeout)

      # Test reset functionality
      click_button('Reset count')
      expect(page).to have_content('Button clicked: 0 times', wait: render_timeout)
    end
  end

  describe 'Component composition' do
    it 'renders nested Card components correctly' do
      visit '/shadcn_demo'

      # Wait for components to render - use content-based assertions
      expect(page).to have_content('shadcn/ui Integration Test', wait: render_timeout)
      expect(page).to have_content('Testing CVA', wait: render_timeout)

      # Verify buttons are present (Card footer contains Reset)
      expect(page).to have_button('Click me', wait: render_timeout)
      expect(page).to have_button('Change variant', wait: render_timeout)
      expect(page).to have_button('Reset count', wait: render_timeout)
    end
  end

  describe 'SSR and hydration' do
    it 'correctly hydrates server-rendered content' do
      visit '/shadcn_demo'

      # Component should be marked for hydration
      expect(page).to have_css('[data-component]', wait: render_timeout)
      expect(page).to have_css('[data-island-uuid]', wait: render_timeout)

      # After hydration, interactivity should work
      click_button('Click me')
      expect(page).to have_content('Button clicked: 1 times', wait: render_timeout)
    end
  end
end
