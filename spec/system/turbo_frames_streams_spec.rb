# frozen_string_literal: true

require 'rails_helper'

# Frame renders and stream actions change the page without a Turbo Drive visit
RSpec.describe 'Components a Turbo Frame or Turbo Stream takes off the page', type: :system, js: true do
  def disconnected
    Live::Departing::DISCONNECTED
  end

  def expect_disconnected(*live_ids)
    deadline = 5.seconds.from_now
    sleep 0.05 until (live_ids - disconnected).empty? || Time.current > deadline

    expect(disconnected).to include(*live_ids)
  end

  def bump(id, to:)
    click_button "increment-#{id}"
    expect(page).to have_css("[data-testid=\"count-#{id}\"]", text: to, wait: 5)
  end

  before do
    disconnected.clear
  end

  context 'with a frame' do
    before do
      visit '/turbo/frame'
      expect(page).to have_selector('[data-live-status-value="subscribed"]', count: 2, wait: 5)
      bump('framed', to: '1')
    end

    it 'disconnects them, and the children they render, when a frame navigation drops them' do
      click_link 'Leave'

      expect(page).to have_css('[data-testid="frame-empty"]')
      expect_disconnected('departing/framed', 'departing/framed-child')
    end

    it 'keeps them, and their state, when the frame renders them again' do
      click_link 'Stay'

      expect(page).to have_css('[data-testid="frame-tab"]', text: 'other')
      expect(page).to have_css('[data-testid="count-framed"]', text: '1')
      bump('framed', to: '2')
      bump('framed-child', to: '1')
      expect(disconnected).to be_empty
    end
  end

  context 'with a stream' do
    before do
      visit '/turbo/stream'
      expect(page).to have_selector('[data-live-status-value="subscribed"]', count: 2, wait: 5)
      bump('streamed', to: '1')
    end

    it 'disconnects them, and the children they render, when a stream removes them' do
      click_button 'Remove'

      expect(page).to have_no_css('[data-testid="departing-streamed"]', wait: 5)
      expect_disconnected('departing/streamed', 'departing/streamed-child')
    end

    it 'keeps one the page holds off the document while a stream changes something else' do
      execute_script(<<~JS)
        window.parked = document.getElementById('departing-item')
        window.parked.remove()
        Turbo.renderStreamMessage('<turbo-stream action="append" target="departing-list"><template><p data-testid="appended">x</p></template></turbo-stream>')
      JS
      expect(page).to have_css('[data-testid="appended"]', wait: 5)

      execute_script("document.getElementById('departing-list').append(window.parked)")

      expect(page).to have_css('[data-testid="count-streamed"]', text: '1')
      bump('streamed', to: '2')
      bump('streamed-child', to: '1')
      expect(disconnected).to be_empty
    end

    it 'keeps them, and their state, when the same stream response puts them back' do
      click_button 'Swap'

      expect(page).to have_selector('[data-live-status-value="subscribed"]', count: 2, wait: 5)
      expect(page).to have_css('[data-testid="count-streamed"]', text: '1')
      bump('streamed', to: '2')
      expect(disconnected).to be_empty
    end

    it 'builds them afresh when a stream adds them again' do
      click_button 'Remove'
      expect(page).to have_no_css('[data-testid="departing-streamed"]', wait: 5)

      click_button 'Add'

      expect(page).to have_selector('[data-live-status-value="subscribed"]', count: 2, wait: 5)
      expect(page).to have_css('[data-testid="count-streamed"]', text: '0')
      bump('streamed', to: '1')
    end
  end
end
