# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Loading States', type: :system, js: true do
  before do
    visit '/loading'

    # Wait for the component to connect
    expect(page).to have_selector('[data-testid="increment-button"]', wait: 5)
  end

  describe 'live-disable-with on an action button' do
    it 'disables the button and swaps its label while the action is in flight' do
      click_button 'increment-button'

      expect(page).to have_button('Working...', disabled: true, wait: 2)
    end

    it 'restores the button and applies the update when the render arrives' do
      click_button 'increment-button'

      expect(page).to have_selector('[data-testid="count"]', text: '1', wait: 5)
      expect(page).to have_button('Increment', disabled: false)
      expect(page).not_to have_button('Working...')
    end
  end

  describe 'live-loading attribute' do
    it 'marks the component root and trigger while in flight' do
      click_button 'increment-button'

      expect(page).to have_selector('[data-testid="loading-root"][live-loading]', wait: 2)
      expect(page).to have_selector('[data-testid="increment-button"][live-loading]', wait: 2)
    end

    it 'clears the attributes after the render arrives' do
      click_button 'increment-button'

      expect(page).to have_selector('[data-testid="count"]', text: '1', wait: 5)
      expect(page).to have_selector('[data-testid="loading-root"]:not([live-loading])')
      expect(page).to have_selector('[data-testid="increment-button"]:not([live-loading])')
    end

    it 'clears the loading state via ack when the action changes nothing' do
      click_button 'noop-button'

      # Loading state appears while the slow no-op action runs...
      expect(page).to have_selector('[data-testid="loading-root"][live-loading]', wait: 2)

      # ...and is cleared by the server ack even though no re-render happens
      expect(page).to have_selector('[data-testid="loading-root"]:not([live-loading])', wait: 5)
      expect(page).to have_selector('[data-testid="noop-button"]:not([live-loading])')
      expect(page).to have_selector('[data-testid="count"]', text: '0')
    end
  end

  describe 'live-disable-with inside a form' do
    it 'disables the submit button while the form action is in flight' do
      fill_in 'title-input', with: 'Hello'
      click_button 'save-button'

      expect(page).to have_button('Saving...', disabled: true, wait: 2)
    end

    it 'submits the form values and restores the button' do
      fill_in 'title-input', with: 'Hello'
      click_button 'save-button'

      expect(page).to have_selector('[data-testid="title"]', text: 'Hello', wait: 5)
      expect(page).to have_button('Save', disabled: false)
    end
  end
end
