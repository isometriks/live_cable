# frozen_string_literal: true

require 'rails_helper'

# A socket is authenticated once, at its handshake, and never sees the
# session again. What the application does to the session afterwards must not
# wedge it, and the application must be able to close it.
RSpec.describe 'Session changes behind an open socket', type: :system, js: true do
  def call_from_page(path)
    page.evaluate_async_script(<<~JS, path)
      const [path, done] = arguments
      fetch(path).then(() => done())
    JS
  end

  before do
    visit '/counter'
    expect(page).to have_selector('[data-live-status-value="subscribed"]', wait: 5)
  end

  it 'keeps processing actions after the session\'s CSRF token rotates, as it does on sign-in' do
    call_from_page('/rotate_session_token')

    click_button 'increment-button'

    expect(page).to have_selector('[data-testid="counter-value"]', text: '1', wait: 5)
    expect(page).to have_no_selector('[live-loading]')
  end

  it 'comes back on a fresh socket when the application disconnects the user\'s sockets' do
    click_button 'increment-button'
    expect(page).to have_selector('[data-testid="counter-value"]', text: '1', wait: 5)

    call_from_page('/disconnect_sockets')

    # The client reconnects by itself once it notices the socket is gone, and
    # the component is rebuilt from its defaults on the new socket
    expect(page).to have_selector('[data-testid="counter-value"]', text: '0', wait: 20)

    click_button 'increment-button'
    expect(page).to have_selector('[data-testid="counter-value"]', text: '1', wait: 5)
  end
end
