# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'An initial lambda reading the component defaults' do
  include LiveCable::Testing

  it 'renders the default on the HTTP prerender' do
    html = ApplicationController.render(inline: "<%= live('default_reader', id: 'r1', owner_id: 7) %>")

    expect(Capybara.string(html)).to have_css('[data-testid="user-id"]', exact_text: '7')
  end

  it 'renders the default once connected' do
    reader = live_mount('default_reader', owner_id: 7)

    expect(reader.user_id).to eq(7)
  end
end
