# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Dependencies read through hash shorthand or empty parentheses' do
  include LiveCable::Testing

  let(:component) { live_mount('shorthand') }

  before { component.perform(:increment) }

  it 're-renders a part that calls the reactive with empty parentheses' do
    expect(component.rendered).to have_css('[data-testid="parens"]', text: '2')
  end

  it 're-renders a part that passes the reactive as a hash shorthand value' do
    expect(component.rendered).to have_css('[data-testid="data"][data-count="2"]')
  end

  it 're-renders a partial given the reactive as a shorthand local' do
    expect(component.rendered).to have_css('[data-testid="badge"]', text: '2')
  end

  it 're-renders a part that passes a template local as a shorthand value' do
    expect(component.rendered).to have_css('[data-testid="total"][data-total="20"]')
  end
end
