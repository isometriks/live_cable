# frozen_string_literal: true

require 'rails_helper'

# ActionCable forgets a subscription the server rejects, so nothing more will
# arrive for the component
RSpec.describe 'A subscription the server rejects', type: :system, js: true do
  it 'marks the component rejected and tells the page' do
    visit '/rejected'

    expect(page).to have_selector('[data-live-status-value="rejected"]', wait: 5)
    expect(page).to have_selector('body[data-rejected="yes"]')
    expect(page).to have_selector('[data-testid="counter-value"]', text: '0')
  end
end
