# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Form Test Component', type: :system, js: true do
  before do
    visit '/form_test'
  end

  it 'displays the form test component' do
    expect(page).to have_selector('[data-testid="form-test-component"]')
    expect(page).to have_content('Form Test Component')
  end

  it 'renders form_with with block correctly' do
    # Verify that form_with block is captured and rendered properly
    expect(page).to have_field('user[name]')
    expect(page).to have_field('user[email]')
  end

  it 'renders fields_for nested block correctly' do
    # Verify that fields_for nested block is captured and rendered properly
    expect(page).to have_field('user[address_attributes][street]')
    expect(page).to have_field('user[address_attributes][city]')
  end

  it 'shows initial values in form fields' do
    expect(page).to have_field('user[name]', with: 'John Doe')
    expect(page).to have_field('user[email]', with: 'john@example.com')
    expect(page).to have_field('user[address_attributes][street]', with: '123 Main St')
    expect(page).to have_field('user[address_attributes][city]', with: 'Anytown')
  end

  it 'shows initial values in display area' do
    expect(page).to have_selector('[data-testid="display-name"]', text: 'John Doe')
    expect(page).to have_selector('[data-testid="display-email"]', text: 'john@example.com')
    expect(page).to have_selector('[data-testid="display-street"]', text: '123 Main St')
    expect(page).to have_selector('[data-testid="display-city"]', text: 'Anytown')
  end

  it 'updates values when form is submitted' do
    # Wait for component to be fully connected and ready
    expect(page).to have_selector('[data-live-status-value="subscribed"]', wait: 5)

    # Clear fields before filling to avoid appending to existing values
    fill_in 'user[name]', with: 'Jane Smith', fill_options: { clear: :backspace }
    fill_in 'user[email]', with: 'jane@example.com', fill_options: { clear: :backspace }
    fill_in 'user[address_attributes][street]', with: '456 Oak Ave', fill_options: { clear: :backspace }
    fill_in 'user[address_attributes][city]', with: 'Springfield', fill_options: { clear: :backspace }

    click_button 'Update'

    # Wait for ActionCable to update the values
    expect(page).to have_selector('[data-testid="display-name"]', text: 'Jane Smith', wait: 5)
    expect(page).to have_selector('[data-testid="display-email"]', text: 'jane@example.com', wait: 5)
    expect(page).to have_selector('[data-testid="display-street"]', text: '456 Oak Ave', wait: 5)
    expect(page).to have_selector('[data-testid="display-city"]', text: 'Springfield', wait: 5)

    # Verify form fields also updated
    expect(page).to have_field('user[name]', with: 'Jane Smith')
    expect(page).to have_field('user[email]', with: 'jane@example.com')
    expect(page).to have_field('user[address_attributes][street]', with: '456 Oak Ave')
    expect(page).to have_field('user[address_attributes][city]', with: 'Springfield')
  end
end
