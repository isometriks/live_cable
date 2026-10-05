# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Reactive inputs', type: :system, js: true do
  before do
    visit '/reactive_inputs'
    expect(page).to have_selector('[data-live-status-value="subscribed"]', wait: 5)
  end

  it 'checks and unchecks a checkbox' do
    check 'notify'
    expect(page).to have_selector('[data-testid="notify"]', text: 'true', wait: 5)
    expect(page).to have_checked_field('notify')

    uncheck 'notify'
    expect(page).to have_selector('[data-testid="notify"]', text: 'false', wait: 5)
    expect(page).to have_unchecked_field('notify')

    check 'notify'
    expect(page).to have_selector('[data-testid="notify"]', text: 'true', wait: 5)
  end

  it 'sends every selected option of a multiple select' do
    select 'b', from: 'tags'
    expect(page).to have_selector('[data-testid="tags"]', text: '["b"]', wait: 5)

    select 'c', from: 'tags'
    expect(page).to have_selector('[data-testid="tags"]', text: '["b", "c"]', wait: 5)
    expect(page).to have_select('tags', selected: %w[b c])

    unselect 'b', from: 'tags'
    expect(page).to have_selector('[data-testid="tags"]', text: '["c"]', wait: 5)
  end

  it 'sends the chosen radio value' do
    choose 'size', option: 'm'
    expect(page).to have_selector('[data-testid="size"]', text: '"m"', wait: 5)
    expect(page).to have_checked_field('size', with: 'm')
  end
end
