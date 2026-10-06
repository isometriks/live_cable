# frozen_string_literal: true

require 'rails_helper'

# Turbo keeps the socket open across a sign-in, so it would carry on as
# whoever opened it
RSpec.describe 'Signing in as someone else without leaving the page', type: :system, js: true do
  it 'reopens the socket so components act for the new session' do
    visit '/whoami'
    expect(page).to have_selector('[data-testid="whoami"]', text: 'guest', wait: 5)

    click_link 'Sign in as bob'

    expect(page).to have_selector('[data-testid="signed-in-as"]', text: 'bob', wait: 5)
    expect(page).to have_selector('[data-testid="whoami"]', text: 'bob', wait: 10)
  end
end
