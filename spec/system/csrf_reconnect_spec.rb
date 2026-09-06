# frozen_string_literal: true

require 'rails_helper'

# A LiveCable::Connection validates message tokens against the session it
# captured at the WebSocket handshake. When the session's token rotates
# behind an open socket (Devise does this on every sign-in), every page
# rendered from then on carries a token the socket cannot verify.
RSpec.describe 'CSRF token rotated behind an open socket', type: :system, js: true do
  # Rotate the session in the browser and give the page the token a fresh
  # render would carry, leaving the already-open socket on the old session.
  def rotate_session_csrf_token
    page.evaluate_async_script(<<~JS)
      const done = arguments[0]
      fetch('/rotate_csrf')
        .then(response => response.json())
        .then(({ token }) => {
          document.querySelector("meta[name='csrf-token']").setAttribute('content', token)
          done(token)
        })
    JS
  end

  before do
    visit '/counter'
    expect(page).to have_selector('[data-live-status-value="subscribed"]', wait: 5)
    rotate_session_csrf_token
  end

  it 'still processes the next action instead of leaving it hanging' do
    click_button 'increment-button'

    expect(page).to have_selector('[data-testid="counter-value"]', text: '1', wait: 5)
    expect(page).to have_no_selector('[live-loading]')
  end

  it 'keeps working on the socket it reconnected' do
    click_button 'increment-button'
    expect(page).to have_selector('[data-testid="counter-value"]', text: '1', wait: 5)

    click_button 'increment-button'
    expect(page).to have_selector('[data-testid="counter-value"]', text: '2', wait: 5)
  end

  context 'when the page itself was rendered before the session rotated' do
    before do
      # The session rotates again after this page took its token, so the
      # token on the page verifies against neither the socket's session nor
      # the current one - only a token from a fresh socket will do
      page.evaluate_async_script(<<~JS)
        const done = arguments[0]
        fetch('/rotate_csrf').then(() => done())
      JS
      page.execute_script('window.notReloaded = true')
    end

    it 'recovers with the token the fresh socket issues instead of reloading' do
      click_button 'increment-button'

      expect(page).to have_selector('[data-testid="counter-value"]', text: '1', wait: 5)
      expect(page.evaluate_script('window.notReloaded')).to be(true)
      expect(page).to have_no_selector('[live-loading]')
    end
  end
end
