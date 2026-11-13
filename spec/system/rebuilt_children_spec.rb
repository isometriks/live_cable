# frozen_string_literal: true

require 'rails_helper'

# The client closes a rebuilt parent's children, but ActionCable may run the
# new parent's subscribe before some of those unsubscribes
RSpec.describe 'A Turbo visit that builds a parent with several children again', type: :system, js: true do
  it 'builds every child again from the new defaults' do
    visit '/panel?account=1'
    expect(page).to have_selector('[data-live-status-value="subscribed"]', count: 7, wait: 5)
    within('[data-testid="slot-1"]') { click_button 'increment-button' }
    within('[data-testid="slot-1"]') { expect(page).to have_css('[data-testid="counter-value"]', text: '12') }

    click_link 'Account 2'

    expect(page).to have_css('[data-testid="panel-account"]', text: 'Account 2')
    6.times do |i|
      within("[data-testid=\"slot-#{i}\"]") { expect(page).to have_css('[data-testid="counter-value"]', text: 20 + i) }
    end
    expect(page).to have_selector('[data-live-status-value="subscribed"]', count: 7, wait: 5)

    within('[data-testid="slot-1"]') { click_button 'increment-button' }

    within('[data-testid="slot-1"]') { expect(page).to have_css('[data-testid="counter-value"]', text: '22') }
  end
end

RSpec.describe 'A parent rendered again with other defaults outside a Turbo Drive visit', type: :system, js: true do
  def expect_shell_rebuilt
    expect(page).to have_css('[data-testid="shell-account"]', text: 'Account 5', wait: 5)
    expect(page).to have_css('[data-testid="counter-value"]', text: '5', wait: 5)
    expect(page).to have_selector('[data-live-status-value="subscribed"]', count: 2, wait: 5)

    click_button 'increment-button'

    expect(page).to have_css('[data-testid="counter-value"]', text: '6', wait: 5)
  end

  def bump_child
    expect(page).to have_selector('[data-live-status-value="subscribed"]', count: 2, wait: 5)
    click_button 'increment-button'
    expect(page).to have_css('[data-testid="counter-value"]', text: '2', wait: 5)
  end

  it 'builds its child again after a frame navigation' do
    visit '/shell_frame?account=1'
    bump_child

    click_link 'Account 5'

    expect_shell_rebuilt
    expect(page).to have_current_path('/shell_frame?account=1')
  end

  it 'builds its child again after a Turbo Stream replace' do
    visit '/shell_stream?account=1'
    bump_child

    click_button 'Account 5'

    expect_shell_rebuilt
  end
end
