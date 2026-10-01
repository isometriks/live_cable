# frozen_string_literal: true

require 'rails_helper'

# A Turbo visit to a page that renders the same parent, whose child is
# rendered inline and has no live id of its own on the page
RSpec.describe 'Navigating to a page that renders the same parent', type: :system, js: true do
  before do
    visit '/shell?account=1'
    expect(page).to have_selector('[data-live-status-value="subscribed"]', count: 2, wait: 5)
    click_button 'increment-button'
    expect(page).to have_selector('[data-testid="counter-value"]', text: '2', wait: 5)
  end

  it 'keeps the child and its state when the parent keeps its defaults' do
    click_link 'Account 1, another tab'

    expect(page).to have_current_path('/shell?account=1&tab=other')
    expect(page).to have_selector('[data-testid="counter-value"]', text: '2', wait: 5)

    click_button 'increment-button'

    expect(page).to have_selector('[data-testid="counter-value"]', text: '3', wait: 5)
  end

  it 'builds the child again from the parent when the parent\'s defaults differ' do
    click_link 'Account 5'

    expect(page).to have_selector('[data-testid="shell-account"]', text: 'Account 5', wait: 5)
    expect(page).to have_selector('[data-testid="counter-value"]', text: '5', wait: 5)
    expect(page).to have_selector('[data-live-status-value="subscribed"]', count: 2, wait: 5)

    click_button 'increment-button'

    expect(page).to have_selector('[data-testid="counter-value"]', text: '6', wait: 5)
  end
end

# Turbo carries a data-turbo-permanent element over to the new page and drops
# the new page's copy of it
RSpec.describe 'Navigating with a parent Turbo keeps on the page', type: :system, js: true do
  it 'keeps the child and its state whatever defaults the new page gives the parent' do
    visit '/shell?account=1&permanent=1'
    expect(page).to have_selector('[data-live-status-value="subscribed"]', count: 2, wait: 5)
    click_button 'increment-button'
    expect(page).to have_selector('[data-testid="counter-value"]', text: '2', wait: 5)

    click_link 'Account 5, kept'

    expect(page).to have_current_path('/shell?account=5&permanent=1')
    expect(page).to have_selector('[data-testid="shell-account"]', text: 'Account 1')

    click_button 'increment-button'

    expect(page).to have_selector('[data-testid="counter-value"]', text: '3', wait: 5)
  end
end
