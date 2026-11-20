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

  context 'with a burst of messages' do
    # Debug logging to stdout yields between the server's jobs often enough
    # to hide them running out of order
    around do |example|
      level = Rails.logger.level
      Rails.logger.level = :info
      example.run
    ensure
      Rails.logger.level = level
    end

    it 'sends what was typed when Enter follows the typing' do
      find('[data-testid="message-input"]').send_keys('the quick brown fox', :enter)

      expect(page).to have_selector('[data-testid="sent"]', text: 'the quick brown fox', wait: 5)
      expect(page).to have_no_selector('[live-loading]', wait: 5)
      expect(page).to have_selector('[data-testid="message"]', exact_text: '""')
      expect(find('[data-testid="message-input"]').value).to eq('')
      expect(all('[data-testid="sent"]').map(&:text)).to eq(['the quick brown fox'])
    end
  end
end
