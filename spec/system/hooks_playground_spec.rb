# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Hooks Playground', type: :system, js: true do
  def expect_hook_snapshots(test_id:, expected_effect:, expected_layout:)
    expect(page).to have_css("[data-testid='#{test_id}-effect']", text: /#{expected_effect}/i, wait: 10)
    expect(page).to have_css("[data-testid='#{test_id}-layout']", text: /#{expected_layout}/i)
  end

  def interact_with_playground(test_id:)
    state_selector = "[data-testid='#{test_id}-state']"
    expect(page).to have_css(state_selector, text: /State:/, wait: 10)

    find("[data-testid='#{test_id}-increment']").click
    expect(page).to have_css(state_selector, text: /State: \d+/, wait: 5)

    find("[data-testid='#{test_id}-burst']").click
    expect(page).to have_css(state_selector, text: /State: \d+/, wait: 5)

    find("[data-testid='#{test_id}-text-append']").click
    expect(page).to have_css("[data-testid='#{test_id}-text']", text: /!|\?/i, wait: 5)

    find("[data-testid='#{test_id}-items-add']").click
    expect(page).to have_css("[data-testid='#{test_id}-items'] li", minimum: 1, wait: 5)

    expect(page).to have_css("[data-testid='#{test_id}-ref']", text: /count-/)
  end

  it 'exercises all hooks inside island components' do
    visit '/hooks_playground'

    expect_hook_snapshots(test_id: 'tsx-island', expected_effect: 'effect-ran', expected_layout: 'layout-ran')
    expect_hook_snapshots(test_id: 'jsx-island', expected_effect: 'effect-jump', expected_layout: 'layout-finished')

    interact_with_playground(test_id: 'tsx-island')
    interact_with_playground(test_id: 'jsx-island')
  end

  it 'reuses the hooks playground component inside full-page TSX' do
    visit '/pages/hooks_playground_tsx'
    expect_hook_snapshots(test_id: 'tsx-full-page', expected_effect: 'effect-ran', expected_layout: 'layout-ran')
    interact_with_playground(test_id: 'tsx-full-page')
  end

  it 'reuses the hooks playground component inside full-page JSX' do
    visit '/pages/hooks_playground_jsx'
    expect_hook_snapshots(test_id: 'jsx-full-page', expected_effect: 'effect-jump', expected_layout: 'layout-finished')
    interact_with_playground(test_id: 'jsx-full-page')
  end

  it 'hydrates hooks rendered from the layout slot' do
    visit '/pages/layout_hooks'

    expect_hook_snapshots(test_id: 'layout-page-hooks', expected_effect: 'effect-ran', expected_layout: 'layout-ran')
    interact_with_playground(test_id: 'layout-page-hooks')

    expect_hook_snapshots(test_id: 'layout-hooks', expected_effect: 'effect-ran', expected_layout: 'layout-ran')
    interact_with_playground(test_id: 'layout-hooks')
  end
end
