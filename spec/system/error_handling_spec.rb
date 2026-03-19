# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Error Handling', type: :system, js: true do
  describe 'action errors' do
    before do
      visit '/error_test'
      expect(page).to have_selector('[data-testid="error-test-component"]', wait: 5)
    end

    it 'replaces the component with error details when an action raises' do
      click_button 'Trigger Error'

      expect(page).to have_selector('details', wait: 5)
      expect(page).to have_selector('details summary', text: 'RuntimeError')
      expect(page).to have_content('Something went wrong')
    end

    it 'removes the component element when an error occurs' do
      click_button 'Trigger Error'

      expect(page).not_to have_selector('[data-testid="error-test-component"]', wait: 5)
    end

    it 'includes the component class name in the error summary' do
      click_button 'Trigger Error'

      expect(page).to have_selector('details summary', text: 'Live::ErrorTest', wait: 5)
    end
  end

  describe 'render errors' do
    before do
      visit '/error_test'
      expect(page).to have_selector('[data-testid="error-test-component"]', wait: 5)
    end

    it 'replaces the component with error details when a render raises' do
      click_button 'Trigger Render Error'

      expect(page).to have_selector('details', wait: 5)
      expect(page).not_to have_selector('[data-testid="error-test-component"]')
    end

    it 'includes the component class name in the render error summary' do
      click_button 'Trigger Render Error'

      expect(page).to have_selector('details summary', text: 'Live::ErrorTest', wait: 5)
    end
  end

  describe 'stream callback errors' do
    before do
      visit '/error_test'
      expect(page).to have_selector('[data-testid="error-test-component"]', wait: 5)
    end

    it 'replaces the component with error details when a stream callback raises' do
      click_button 'Subscribe to Error Stream'
      sleep 0.5 # wait for subscription to be registered
      click_button 'Broadcast to Error Stream'

      expect(page).to have_selector('details', wait: 5)
      expect(page).not_to have_selector('[data-testid="error-test-component"]')
    end

    it 'includes the component class name in the stream error summary' do
      click_button 'Subscribe to Error Stream'
      sleep 0.5
      click_button 'Broadcast to Error Stream'

      expect(page).to have_selector('details summary', text: 'Live::ErrorTest', wait: 5)
    end
  end

  describe 'subscribe errors' do
    before do
      visit '/error_on_subscribe_test'
    end

    it 'replaces the component with error details when subscription render raises' do
      expect(page).to have_selector('details', wait: 5)
      expect(page).not_to have_selector('[data-testid="error-on-subscribe-component"]')
    end

    it 'includes the component class name in the subscribe error summary' do
      expect(page).to have_selector('details summary', text: 'Live::ErrorOnSubscribe', wait: 5)
    end
  end
end
