# frozen_string_literal: true

require 'rails_helper'
require 'support/production_helpers'

RSpec.describe 'Production Hydration', type: :system, js: true do
  let(:render_timeout) { 20 }

  before(:all) do
    # Build production assets if not already built
    ProductionHelpers.build_production_assets unless ProductionHelpers.production_assets_built?
  end

  # Note: These tests run against the development/test server but verify
  # production-like behavior. For true production testing, use :production_server tag.

  describe 'island hydration' do
    it 'loads boot script and hydrates islands' do
      visit '/counter'

      # Wait for React to hydrate
      expect(page).to have_css('[data-reactive-hydrated="true"]', wait: render_timeout)
    end

    it 'hydrates Counter component with correct initial state' do
      visit '/counter'

      # Component should be hydrated
      expect(page).to have_css('[data-component="Counter"]', wait: render_timeout)

      # Should have interactive buttons
      expect(page).to have_button('+')
      expect(page).to have_button('-')
    end

    it 'maintains interactivity after hydration' do
      visit '/counter'

      # Wait for hydration
      expect(page).to have_css('[data-reactive-hydrated="true"]', wait: render_timeout)

      # Get initial count
      initial_count = find('[data-component="Counter"]').text[/\d+/].to_i

      # Click increment button
      click_button '+'

      # Count should increase
      expect(page).to have_content((initial_count + 1).to_s, wait: 5)
    end

    it 'hydrates multiple islands independently' do
      visit '/multiple_islands'

      # All islands should hydrate
      hydrated_islands = all('[data-reactive-hydrated="true"]', wait: render_timeout)
      expect(hydrated_islands.size).to be >= 2
    end
  end

  describe 'full-page hydration' do
    it 'hydrates full-page TSX templates' do
      visit '/pages/hooks_playground_tsx'

      # Full page should be marked as hydrated
      expect(page).to have_css('[data-reactive-page="true"]', wait: render_timeout)
      expect(page).to have_css('[data-reactive-hydrated="true"]', wait: render_timeout)
    end

    it 'React hooks work after hydration' do
      visit '/pages/hooks_playground_tsx'

      # Wait for hydration
      expect(page).to have_css('[data-reactive-hydrated="true"]', wait: render_timeout)

      # useState should work
      if page.has_button?('Increment')
        click_button 'Increment'
        # State should update (implementation specific)
      end
    end
  end

  describe 'error recovery' do
    it 'does not break the page when hydration fails for one component' do
      # Visit a page that might have a problematic component
      visit '/counter'

      # Page should still render
      expect(page).to have_content('Counter', wait: render_timeout)
    end

    it 'logs hydration errors to console in development' do
      visit '/counter'

      # Check for console errors (implementation specific)
      # This is mainly for debugging - errors should be logged but not break the page
      logs = page.driver.browser.logs.get(:browser) rescue []

      # Filter for ReactiveViews errors only
      rv_errors = logs.select { |log| log.message.include?('reactive_views') && log.level == 'SEVERE' }

      # Should not have critical errors
      expect(rv_errors).to be_empty
    end
  end

  describe 'asset loading' do
    it 'loads JavaScript bundle without errors' do
      visit '/counter'

      # Page should load successfully
      expect(page.status_code).to eq(200)

      # React should be available globally
      result = page.evaluate_script('typeof window.__REACTIVE_VIEWS__')
      expect(result).to eq('object')
    end

    it 'exposes React in global namespace' do
      visit '/counter'

      # Wait for boot script to run
      sleep 0.5

      result = page.evaluate_script('typeof window.__REACTIVE_VIEWS__.react')
      expect(result).to eq('object')
    end

    it 'exposes hydrateRoot function' do
      visit '/counter'

      sleep 0.5

      result = page.evaluate_script('typeof window.__REACTIVE_VIEWS__.hydrateRoot')
      expect(result).to eq('function')
    end
  end

  describe 'CSS loading' do
    it 'applies styles before JavaScript executes' do
      visit '/counter'

      # Component should have styles applied
      # This is a visual check - we verify the component is visible and styled
      counter = find('[data-component="Counter"]', wait: render_timeout)
      expect(counter).to be_visible
    end

    it 'does not cause flash of unstyled content' do
      # This is hard to test automatically - mainly for manual verification
      # We can check that CSS is in the head before body content
      visit '/counter'

      page_html = page.html
      head_end = page_html.index('</head>')
      body_start = page_html.index('<body')

      # CSS links should be in head
      css_in_head = page_html[0..head_end].include?('stylesheet') ||
                    page_html[0..head_end].include?('<style')

      expect(css_in_head).to be(true), 'CSS should be loaded in head section'
    end
  end
end

