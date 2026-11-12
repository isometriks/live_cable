# frozen_string_literal: true

require 'rails_helper'

# A refused child stays as it was while its parent keeps rendering it
RSpec.describe 'A child that refuses', type: :system, js: true do
  it 'stays refused when its parent renders again' do
    visit '/guest_list'
    expect(page).to have_selector('[data-testid="guest-a"][data-live-status-value="subscribed"]', wait: 5)

    click_button 'ping-a'
    expect(page).to have_selector('[data-testid="pings-a"]', text: '1', wait: 5)
    click_button 'leave-a'
    expect(page).to have_selector('[data-testid="guest-a"][data-live-status-value="refused"]', wait: 5)

    click_button 'tick'
    expect(page).to have_selector('[data-testid="ticks"]', text: '1', wait: 5)
    click_button 'ping-a'
    click_button 'ping-b'
    expect(page).to have_selector('[data-testid="pings-b"]', text: '1', wait: 5)

    expect(page).to have_selector('[data-testid="guest-a"][data-live-status-value="refused"]')
    expect(page).to have_selector('[data-testid="pings-a"]', text: '1')
  end
end
