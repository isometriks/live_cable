# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Initial values on the HTTP prerender' do
  it 'evaluates each initial value once per component' do
    html = Capybara.string(ApplicationController.render(inline: "<%= live('random_field', id: 'f1') %>"))

    expect(html.find('label')['for']).to eq(html.find('input')['id'])
  end
end
