# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Error Handling', type: :system, js: true do
  before do
    visit '/error_test'
    expect(page).to have_selector('[data-testid="error-test-component"]', wait: 5)
  end

  it 'replaces the component with error details when an action raises' do
    click_button 'Trigger Error'

    expect(page).to have_selector('details', wait: 5)
    expect(page).to have_selector('details summary', text: 'RuntimeError')
    expect(page).to have_content('Something went wrong')
  end

  it 'removes the component element when an error occurs' do
    click_button 'Trigger Error'

    expect(page).not_to have_selector('[data-testid="error-test-component"]', wait: 5)
  end

  it 'includes the component class name in the error summary' do
    click_button 'Trigger Error'

    expect(page).to have_selector('details summary', text: 'Live::ErrorTest', wait: 5)
  end
end
