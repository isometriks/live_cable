# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'A component rendered over the socket for the page it is on', type: :system, js: true do
  around do |example|
    forgery = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = forgery
  end

  it 'keeps a working authenticity token in its forms' do
    visit '/page_context'
    click_button 'bump'
    expect(page).to have_css('[data-testid="count"]', text: '1')

    expect(page).to have_css('[data-testid="root-url"]', text: "#{Capybara.current_session.server.base_url}/")

    click_button 'Submit'

    expect(page).to have_content('submitted')
  end
end
