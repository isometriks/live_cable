# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Plain ERB Template', type: :system, js: true do
  before do
    visit '/plain_erb'
    expect(page).to have_selector('[data-testid="plain-erb-component"]', wait: 5)
  end

  it 'renders the initial state' do
    expect(page).to have_selector('[data-testid="count-value"]', text: '0')
  end

  it 'updates reactively when an action is triggered' do
    expect(page).to have_selector('[data-testid="count-value"]', text: '0')

    click_button 'increment-button'

    expect(page).to have_selector('[data-testid="count-value"]', text: '1', wait: 5)
  end

  it 'continues to update across multiple actions' do
    click_button 'increment-button'
    expect(page).to have_selector('[data-testid="count-value"]', text: '1', wait: 5)

    click_button 'increment-button'
    expect(page).to have_selector('[data-testid="count-value"]', text: '2', wait: 5)

    click_button 'increment-button'
    expect(page).to have_selector('[data-testid="count-value"]', text: '3', wait: 5)
  end
end

RSpec.describe 'Plain ERB child whose before_render halts', type: :system, js: true do
  it 'keeps what it last rendered when its parent renders again' do
    visit '/plain_guard'
    expect(page).to have_selector('[data-testid="plain-guarded"]', text: 'guarded 0', wait: 5)

    click_button 'block-button'

    expect(page).to have_selector('[data-testid="count"]', text: '1', wait: 5)
    expect(page).to have_selector('[data-testid="plain-guarded"]', text: 'guarded 0')
  end
end
