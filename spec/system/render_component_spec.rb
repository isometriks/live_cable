# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Render Component Instances', type: :system, js: true do
  before do
    visit '/render_component'
    expect(page).to have_selector('[data-testid="render-component"]', wait: 5)
  end

  it 'renders a component instance via render() in the template' do
    expect(page).to have_selector('[data-testid="badge"]', text: 'Count: 1')
  end

  it 'updates the rendered component instance after state changes' do
    expect(page).to have_selector('[data-testid="badge"]', text: 'Count: 1')

    click_button 'increment-button'

    expect(page).to have_selector('[data-testid="badge"]', text: 'Count: 2', wait: 5)
  end
end
