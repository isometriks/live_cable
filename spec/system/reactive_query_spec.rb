# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'reactive_query', type: :system, js: true do
  before do
    Chore.create_tables
    Chore.create!(name: 'Laundry')

    visit '/chores'
  end

  it 'shows a row written elsewhere once a broadcast refreshes the query' do
    Chore.create!(name: 'Garden')
    ActionCable.server.broadcast('chores', {})

    expect(page).to have_css('[data-testid="chore"]', text: 'Garden')
    expect(page).to have_css('[data-testid="summary"]', text: '2 to do')
  end

  it 'shows a row the component wrote in an action' do
    find('[data-testid="name"]').fill_in(with: 'Dishes')
    click_button 'add'

    expect(page).to have_css('[data-testid="chore"]', text: 'Dishes')
  end
end
