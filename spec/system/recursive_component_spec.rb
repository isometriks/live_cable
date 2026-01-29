# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Recursive Component', type: :system, js: true do
  before do
    visit '/recursive'
  end

  it 'displays the recursive component' do
    expect(page).to have_selector('[data-testid="recursive-component"]')
    expect(page).to have_content('Recursive Component Test')
  end

  it 'shows initial root component with collapsed state' do
    expect(page).to have_selector('[data-testid="label-recursive/root"]', text: 'Root')
    expect(page).to have_selector('[data-testid="toggle-recursive/root"]', text: '+')
    expect(page).not_to have_selector('[data-testid="child-container-recursive/root"]')
  end

  it 'expands to show child component when toggle button is clicked' do
    # Click toggle button to expand
    find('[data-testid="toggle-recursive/root"]').click

    # Wait for the component to expand and show minus sign
    expect(page).to have_selector('[data-testid="toggle-recursive/root"]', text: '−', wait: 5)

    # Check that child container appears
    expect(page).to have_selector('[data-testid="child-container-recursive/root"]', wait: 5)

    # Check that child component is rendered
    expect(page).to have_selector('[data-testid="label-recursive/root-child"]', text: 'Root.1', wait: 5)
  end

  it 'collapses to hide child component when toggle button is clicked again' do
    # First expand
    find('[data-testid="toggle-recursive/root"]').click
    expect(page).to have_selector('[data-testid="label-recursive/root-child"]', text: 'Root.1', wait: 5)

    # Then collapse
    find('[data-testid="toggle-recursive/root"]').click
    expect(page).to have_selector('[data-testid="toggle-recursive/root"]', text: '+', wait: 5)

    # Child should be removed
    expect(page).not_to have_selector('[data-testid="label-recursive/root-child"]')
  end

  it 'allows multiple levels of nesting' do
    # Expand root
    find('[data-testid="toggle-recursive/root"]').click
    expect(page).to have_selector('[data-testid="label-recursive/root-child"]', text: 'Root.1', wait: 5)

    # Expand first child
    find('[data-testid="toggle-recursive/root-child"]').click
    expect(page).to have_selector('[data-testid="label-recursive/root-child-child"]', text: 'Root.1.2', wait: 5)

    # Expand second child
    find('[data-testid="toggle-recursive/root-child-child"]').click
    expect(page).to have_selector('[data-testid="label-recursive/root-child-child-child"]', text: 'Root.1.2.3', wait: 5)
  end

  it 'maintains independent state for each recursive instance' do
    # Expand root
    find('[data-testid="toggle-recursive/root"]').click
    expect(page).to have_selector('[data-testid="label-recursive/root-child"]', text: 'Root.1', wait: 5)

    # Root should show expanded (−)
    expect(page).to have_selector('[data-testid="toggle-recursive/root"]', text: '−')

    # Child should show collapsed (+)
    expect(page).to have_selector('[data-testid="toggle-recursive/root-child"]', text: '+')

    # Collapse root
    find('[data-testid="toggle-recursive/root"]').click
    expect(page).to have_selector('[data-testid="toggle-recursive/root"]', text: '+', wait: 5)

    # Re-expand root - child should still be collapsed (state maintained)
    find('[data-testid="toggle-recursive/root"]').click
    expect(page).to have_selector('[data-testid="toggle-recursive/root-child"]', text: '+', wait: 5)
  end
end
