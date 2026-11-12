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
end
