# frozen_string_literal: true

require 'rails_helper'

# A Turbo visit to a page that renders a component already live on this one
RSpec.describe 'Navigating to a page that renders the same component', type: :system, js: true do
  before do
    visit '/tenant?account=1'
    expect(page).to have_selector('[data-live-status-value="subscribed"]', wait: 5)
    click_button 'increment-button'
    expect(page).to have_selector('[data-testid="counter-value"]', text: '2', wait: 5)
  end

  it 'keeps the component and its state when its defaults are the same' do
    click_link 'Account 1, another tab'

    expect(page).to have_current_path('/tenant?account=1&tab=other')
    expect(page).to have_selector('[data-testid="counter-value"]', text: '2', wait: 5)
  end

  it 'builds the component again from the new page\'s defaults when they differ' do
    click_link 'Account 5'

    expect(page).to have_selector('[data-testid="account"]', text: 'Account 5', wait: 5)
    expect(page).to have_selector('[data-live-status-value="subscribed"]', wait: 5)
    click_button 'increment-button'

    # The previous account's component would have gone from 2 to 3
    expect(page).to have_selector('[data-testid="counter-value"]', text: '6', wait: 5)
  end
end
