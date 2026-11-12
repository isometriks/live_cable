# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Live partials', type: :system, js: true do
  before do
    visit '/live_partials'
    expect(page).to have_selector('[data-live-id-value="chat"][data-live-status-value="subscribed"]', wait: 5)
  end

  it 'sends actions and reactive inputs in a partial to the component that renders it' do
    find('[data-testid="composer"]').fill_in(with: 'hello')
    expect(page).to have_selector('[data-testid="draft"]', text: 'hello', wait: 5)

    click_on 'Bump 1'

    expect(page).to have_button('Bump 2', wait: 5)
    expect(page).to have_selector('[data-testid="badge-lobby"]', text: 'Lobby: 2')
    expect(page).to have_selector('[data-testid="scaled"]', text: '20')
    expect(page).to have_field('draft', with: 'hello')
  end
end
