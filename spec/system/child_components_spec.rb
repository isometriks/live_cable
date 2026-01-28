# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Child Components', type: :system, js: true do
  before do
    visit '/children'
  end

  it 'displays the parent component with one child' do
    expect(page).to have_selector('[data-testid="parent-component"]')
    expect(page).to have_selector('[data-testid="child-component"]', count: 1)
    expect(page).to have_content('Live Parent')
  end

  it 'is able to pass defaults when creating components on the fly' do
    expect(page).to have_content('Child 0')
  end

  it 'adds another child when you click add' do
    click_button 'add-button'

    # Wait for ActionCable to update the value
    expect(page).to have_selector('[data-testid="child-component"]', count: 2)
    expect(page).to have_content('Child 0')
    expect(page).to have_content('Child 1')
  end

  it 'does not render excessively' do
    expect(page).to have_selector('[data-testid="child-component"]', count: 1)
    expect(page).to have_content('Child 0 - 1 render')

    click_button 'add-button'

    expect(page).to have_selector('[data-testid="child-component"]', count: 2)
    expect(page).to have_content('Child 0 - 3 renders')
    expect(page).to have_content('Child 1 - 2 render')

    click_button 'add-button'

    expect(page).to have_selector('[data-testid="child-component"]', count: 3)
    expect(page).to have_content('Child 0 - 4 renders')
    expect(page).to have_content('Child 1 - 3 render')
    expect(page).to have_content('Child 2 - 2 render')
  end
end
