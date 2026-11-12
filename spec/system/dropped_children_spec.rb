# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'A keyed child that moves to another parent', type: :system, js: true do
  before do
    visit '/lanes'
    expect(page).to have_selector('[data-live-status-value="subscribed"]', count: 6, wait: 5)
  end

  [%w[1 todo doing], %w[3 doing todo]].each do |card, from, to|
    it "keeps working and keeps its state when it moves from #{from} to #{to}" do
      click_button "card-note-#{card}"
      expect(page).to have_css("[data-testid=\"card-notes-#{card}\"]", text: '1')

      click_button "card-advance-#{card}"

      expect(page).to have_css("[data-testid=\"lane-#{to}\"] [data-testid=\"card-#{card}\"]")
      expect(page).to have_no_css("[data-testid=\"lane-#{from}\"] [data-testid=\"card-#{card}\"]")
      expect(page).to have_css("[data-testid=\"card-notes-#{card}\"]", text: '1')

      click_button "card-note-#{card}"

      expect(page).to have_css("[data-testid=\"card-notes-#{card}\"]", text: '2')
    end
  end
end

RSpec.describe 'A child hidden and shown again before the first reply', type: :system, js: true do
  it 'comes back working' do
    visit '/toggle'
    expect(page).to have_selector('[data-live-status-value="subscribed"]', count: 2, wait: 5)
    click_button 'increment-button'
    expect(page).to have_css('[data-testid="counter-value"]', text: '1')

    execute_script(<<~JS)
      const flip = document.querySelector('[data-testid="flip"]')
      flip.click()
      flip.click()
    JS

    expect(page).to have_css('[data-testid="visible"]', text: 'true')
    expect(page).to have_css('[data-testid="counter-value"]', text: '0', wait: 5)
    expect(page).to have_selector('[data-live-status-value="subscribed"]', count: 2, wait: 5)

    click_button 'increment-button'

    expect(page).to have_css('[data-testid="counter-value"]', text: '1', wait: 5)
  end
end
