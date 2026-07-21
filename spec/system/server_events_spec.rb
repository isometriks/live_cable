# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Server Events', type: :system, js: true do
  before do
    visit '/event_test'

    expect(page).to have_selector('[data-testid="add-button"]', wait: 5)
  end

  it 'fires a bubbling CustomEvent after the DOM has been morphed' do
    click_button 'add-button'

    # dom=1 proves the new item was already rendered when the event fired
    expect(page).to have_selector('[data-testid="event-log"]', text: 'item-added:1:dom=1', wait: 5)
  end

  it 'fires events even when the action does not re-render' do
    click_button 'ping-button'

    expect(page).to have_selector('[data-testid="event-log"]', text: 'pinged', wait: 5)
    expect(page).to have_selector('[data-testid="event-item"]', count: 0)
  end

  it 'dispatches window events on window' do
    click_button 'window-button'

    expect(page).to have_selector('[data-testid="event-log"]', text: 'window-pinged', wait: 5)
  end

  it 'fires one event per action across multiple clicks' do
    click_button 'add-button'
    expect(page).to have_selector('[data-testid="event-log"]', text: 'item-added:1:dom=1', wait: 5)

    click_button 'add-button'
    expect(page).to have_selector(
      '[data-testid="event-log"]',
      text: 'item-added:1:dom=1;item-added:2:dom=2;',
      wait: 5
    )
  end
end
