# frozen_string_literal: true

require 'rails_helper'

# ActionCable stops reconnecting once the server refuses a handshake, so the
# components must not wait for a reconnect that never comes
RSpec.describe 'A socket the server refuses', type: :system, js: true do
  it 'marks the components refused and tells the page why' do
    visit '/counter'
    expect(page).to have_selector('[data-live-status-value="subscribed"]', wait: 5)

    page.evaluate_async_script(<<~JS)
      const done = arguments[0]
      window.refusals = []
      document.addEventListener('live:refused', (event) => window.refusals.push(event.detail))
      fetch('/revoke_session').then(() => done())
    JS

    expect(page).to have_selector('[data-live-status-value="refused"]', wait: 20)
    expect(page.evaluate_script('window.refusals')).to eq([{ 'reason' => 'unauthorized', 'components' => 1 }])
  end

  # The component is kept across the visit, so nothing else would open a socket
  it 'comes back when the user signs in again without leaving the page' do
    visit '/whoami'
    expect(page).to have_selector('[data-testid="whoami"]', text: 'guest', wait: 5)

    page.evaluate_async_script("fetch('/revoke_session').then(() => arguments[0]())")
    expect(page).to have_selector('[data-live-status-value="refused"]', wait: 20)

    click_link 'Sign in as bob'

    expect(page).to have_selector('[data-testid="signed-in-as"]', text: 'bob', wait: 5)
    expect(page).to have_selector('[data-testid="whoami"]', text: 'bob', wait: 10)
    expect(page).to have_selector('[data-live-status-value="subscribed"]')
  end
end
