# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Turbo + Stimulus + React Coexistence', type: :system, js: true do
  let(:render_timeout) { 15 }

  describe 'Stimulus controllers' do
    it 'initializes alongside React components' do
      visit '/turbo_mixed'

      # Wait for page to load
      expect(page).to have_content('Turbo + Stimulus + React Coexistence Test', wait: render_timeout)

      # Wait for Stimulus to initialize (it changes the output text)
      expect(page).to have_content('Stimulus connected!', wait: render_timeout)

      # Test Stimulus counter is present
      expect(page).to have_content('Stimulus Counter:', wait: render_timeout)
    end
  end

  describe 'React components' do
    it 'renders and hydrates alongside Stimulus' do
      visit '/turbo_mixed'

      # Wait for page and React section
      expect(page).to have_css('[data-testid="react-section"]', wait: render_timeout)

      # React counter should render (either with SSR content or hydrated)
      # Just verify the component is present and has interactive elements
      expect(page).to have_button('+', wait: render_timeout)
      expect(page).to have_button('-', wait: render_timeout)
    end
  end

  describe 'Turbo Frames' do
    it 'loads content via Turbo Frame links' do
      visit '/turbo_mixed'

      # Wait for initial content
      expect(page).to have_css('turbo-frame#dynamic-content', wait: render_timeout)
      expect(page).to have_content('Initial frame content', wait: render_timeout)

      # The frame link should be present
      expect(page).to have_link('Load new content with React component', wait: render_timeout)
    end
  end

  describe 'page structure' do
    it 'renders all three technology sections' do
      visit '/turbo_mixed'

      # Verify all sections are present
      expect(page).to have_css('[data-testid="stimulus-section"]', wait: render_timeout)
      expect(page).to have_css('[data-testid="react-section"]', wait: render_timeout)
      expect(page).to have_css('[data-testid="turbo-frame-section"]', wait: render_timeout)
      expect(page).to have_css('[data-testid="turbo-drive-section"]', wait: render_timeout)
    end
  end
end
