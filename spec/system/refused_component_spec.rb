# frozen_string_literal: true

require 'rails_helper'

# A component that calls refuse! stops, as a refused socket does, rather than
# turning into an error box
RSpec.describe 'A component that refuses', type: :system, js: true do
  it 'keeps its markup, marks itself refused and tells the page why' do
    visit '/revocable'
    expect(page).to have_selector('[data-live-status-value="subscribed"]', wait: 5)

    click_button 'revocable-increment'
    expect(page).to have_selector('[data-testid="revocable-count"]', text: '1', wait: 5)

    click_button 'revocable-leave'

    expect(page).to have_selector('[data-live-status-value="refused"]', wait: 5)
    expect(page).to have_selector('body[data-refused-for="membership_ended"]')
    expect(page).to have_selector('[data-testid="revocable-count"]', text: '1')
    expect(page).to have_no_selector('details')
    expect(page).to have_no_selector('[live-loading]')
  end
end
