# frozen_string_literal: true

require 'rails_helper'

# Turbo restores a cached snapshot on Back unless the page says not to
RSpec.describe 'Back to a page whose live component came after it loaded', type: :system, js: true do
  it 'fetches the page again rather than restore a snapshot of the component' do
    visit '/turbo/stream?empty=1'
    rendered_at = find('[data-testid="rendered-at"]').text

    click_button 'Add'
    expect(page).to have_selector('[data-live-status-value="subscribed"]', count: 2, wait: 5)
    click_button 'increment-streamed'
    expect(page).to have_css('[data-testid="count-streamed"]', text: '1', wait: 5)

    click_link 'Elsewhere'
    expect(page).to have_css('[data-testid="frame-empty"]', wait: 5)
    page.go_back

    expect(page).to have_css('[data-testid="rendered-at"]', wait: 5)
    expect(page).to have_no_css('[data-testid="rendered-at"]', text: rendered_at, wait: 5)
    expect(page).to have_no_css('[data-testid="departing-streamed"]')
  end
end
