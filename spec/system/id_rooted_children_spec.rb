# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'A child component whose root element has an id', type: :system, js: true do
  it 'updates on its first action after the page loads' do
    visit '/shelf'
    expect(page).to have_selector('#shelf-item-first[data-live-status-value="subscribed"]', wait: 5)

    click_button 'Add one'

    expect(page).to have_css('#shelf-item-first [data-testid="item-count"]', exact_text: '1')
  end
end
