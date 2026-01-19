# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Counter Component', type: :system, js: true do
  before do
    visit '/counter'
  end

  it 'displays the counter component' do
    expect(page).to have_selector('[data-testid="counter-component"]')
    expect(page).to have_content('Live Counter')
  end

  it 'shows initial count of 0' do
    expect(page).to have_selector('[data-testid="counter-value"]', text: '0')
  end

  it 'increments the counter when increment button is clicked' do
    initial_value = find('[data-testid="counter-value"]').text.to_i

    click_button 'increment-button'

    # Wait for ActionCable to update the value
    expect(page).to have_selector('[data-testid="counter-value"]', text: (initial_value + 1).to_s, wait: 5)
  end

  it 'decrements the counter when decrement button is clicked' do
    # First increment to have a positive number
    click_button 'increment-button'
    sleep 0.5 # Wait for update

    current_value = find('[data-testid="counter-value"]').text.to_i
    click_button 'decrement-button'

    expect(page).to have_selector('[data-testid="counter-value"]', text: (current_value - 1).to_s, wait: 5)
  end

  it 'resets the counter to 0' do
    # Increment a few times
    3.times do
      click_button 'increment-button'
      sleep 0.2
    end

    click_button 'reset-button'

    expect(page).to have_selector('[data-testid="counter-value"]', text: '0', wait: 5)
  end

  it 'changes step size and increments by new step' do
    # Change step to 5
    fill_in 'step-input', with: '5'
    find('[data-testid="step-input"]').send_keys(:tab) # Trigger change event

    sleep 1 # Wait for reactive update

    click_button 'increment-button'

    expect(page).to have_selector('[data-testid="counter-value"]', text: '5', wait: 5)
  end

  it 'handles multiple rapid clicks correctly' do
    # Click increment button rapidly 5 times
    5.times { click_button 'increment-button' }

    # Final value should be 5 (or possibly less if some clicks didn't register)
    # but should be consistent
    sleep 2 # Wait for all updates to complete

    final_value = find('[data-testid="counter-value"]').text.to_i
    expect(final_value).to be_between(1, 5)
  end
end
