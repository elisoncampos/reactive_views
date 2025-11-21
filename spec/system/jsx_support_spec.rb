# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'JSX Support', type: :system, js: true do
  # Increase timeout for this specific test
  around do |example|
    original_timeout = Capybara.default_max_wait_time
    Capybara.default_max_wait_time = 30
    example.run
    Capybara.default_max_wait_time = original_timeout
  end

  it 'renders a .jsx.erb template' do
    visit '/pages/jsx_test'

    # Check specifically for errors first
    if page.text.include?('Error') || page.text.include?('Exception')
      puts "Page text: #{page.text}"
    end

    # Should find the page content
    expect(page).to have_content('JSX Support Test')
    expect(page).to have_content('Hello from JSX!')

    expect(page).to have_css('.jsx-test')
  end
end
