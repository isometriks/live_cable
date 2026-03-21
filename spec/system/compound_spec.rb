# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Compound Component', type: :system, js: true do
  before do
    visit '/compound'
    expect(page).to have_selector('[data-testid="compound-component"]', wait: 5)
  end

  it 'renders the initial template based on template_state' do
    # count starts at 1 (odd)
    expect(page).to have_selector('[data-testid="odd-template"]')
    expect(page).to have_selector('[data-testid="template-name"]', text: 'odd')
    expect(page).to have_selector('[data-testid="count-value"]', text: '1')
  end

  it 'switches template when the reactive variable changes template_state' do
    expect(page).to have_selector('[data-testid="odd-template"]')

    click_button 'increment-button'

    # count is now 2 (even)
    expect(page).to have_selector('[data-testid="even-template"]', wait: 5)
    expect(page).to have_selector('[data-testid="template-name"]', text: 'even')
    expect(page).to have_selector('[data-testid="count-value"]', text: '2')
  end

  it 'switches back and reflects changes made while other template was active' do
    # Start: count=1, odd template
    expect(page).to have_selector('[data-testid="odd-template"]')
    expect(page).to have_selector('[data-testid="count-value"]', text: '1')

    # Increment to 2 → even template
    click_button 'increment-button'
    expect(page).to have_selector('[data-testid="even-template"]', wait: 5)
    expect(page).to have_selector('[data-testid="count-value"]', text: '2')

    # Increment to 3 → back to odd template with updated count
    click_button 'increment-button'
    expect(page).to have_selector('[data-testid="odd-template"]', wait: 5)
    expect(page).to have_selector('[data-testid="count-value"]', text: '3')
  end

  it 'uses :dynamic rendering when returning to a previously seen template' do
    # Cycle through: odd(1) → even(2) → odd(3) → even(4)
    # Each switch back should use :dynamic to re-render all dynamic parts

    expect(page).to have_selector('[data-testid="count-value"]', text: '1')

    click_button 'increment-button'
    expect(page).to have_selector('[data-testid="count-value"]', text: '2', wait: 5)

    click_button 'increment-button'
    expect(page).to have_selector('[data-testid="count-value"]', text: '3', wait: 5)

    click_button 'increment-button'
    expect(page).to have_selector('[data-testid="count-value"]', text: '4', wait: 5)
    expect(page).to have_selector('[data-testid="even-template"]')
  end
end
