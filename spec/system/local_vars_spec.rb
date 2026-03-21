# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Local Variable Dependency Tracking', type: :system, js: true do
  before do
    visit '/local_vars'
    expect(page).to have_selector('[data-testid="local-vars-component"]', wait: 5)
  end

  describe 'local variable assignment (=)' do
    it 'computes a local from a reactive variable and updates when it changes' do
      expect(page).to have_selector('[data-testid="computed-value"]', text: '0')

      click_button 'increment-button'

      expect(page).to have_selector('[data-testid="computed-value"]', text: '2', wait: 5)
    end
  end

  describe 'local variable or-assign (||=)' do
    it 'uses the fallback value when reactive variable is nil' do
      expect(page).to have_selector('[data-testid="label-value"]', text: 'default_label')
    end

    it 'uses the reactive value once set' do
      click_button 'set-label-button'

      expect(page).to have_selector('[data-testid="label-value"]', text: 'custom', wait: 5)
    end
  end

  describe 'local variable and-assign (&&=)' do
    it 'remains nil when the reactive variable is nil' do
      expect(page).to have_selector('[data-testid="factor-value"]', text: 'nil')
    end

    it 'applies the and-assign expression once the value is set' do
      click_button 'set-multiplier-button'

      expect(page).to have_selector('[data-testid="factor-value"]', text: '30', wait: 5)
    end
  end

  describe 'local dependency propagation across parts' do
    it 'updates downstream parts when an upstream local changes' do
      # computed depends on count, label depends on label reactive var
      # Changing count should update computed but not label
      expect(page).to have_selector('[data-testid="label-value"]', text: 'default_label')
      expect(page).to have_selector('[data-testid="computed-value"]', text: '0')

      click_button 'increment-button'

      expect(page).to have_selector('[data-testid="computed-value"]', text: '2', wait: 5)
      # label should remain unchanged
      expect(page).to have_selector('[data-testid="label-value"]', text: 'default_label')
    end

    it 'handles multiple reactive changes affecting different locals' do
      click_button 'set-label-button'
      expect(page).to have_selector('[data-testid="label-value"]', text: 'custom', wait: 5)

      click_button 'set-multiplier-button'
      expect(page).to have_selector('[data-testid="factor-value"]', text: '30', wait: 5)

      click_button 'increment-button'
      expect(page).to have_selector('[data-testid="computed-value"]', text: '2', wait: 5)

      # Previous values should persist
      expect(page).to have_selector('[data-testid="label-value"]', text: 'custom')
      expect(page).to have_selector('[data-testid="factor-value"]', text: '30')
    end
  end
end
