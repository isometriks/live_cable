# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rendering partials from a .live.erb template' do
  include LiveCable::Testing

  it 'passes the block to a layout partial' do
    component = live_mount('layout_partial')

    expect(component.rendered).to have_css('[data-testid="card"] h2', text: 'Count')
    expect(component.rendered).to have_css('[data-testid="card"] [data-testid="card-count"]', text: '0')
  end

  it 're-renders the block when its dependencies change' do
    component = live_mount('layout_partial')

    component.perform(:increment)

    expect(component.rendered).to have_css('[data-testid="card"] [data-testid="card-count"]', text: '1')
  end
end
