# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Non-reactive shared variables in a .live.erb template' do
  include LiveCable::Testing

  let(:filter) { live_mount('cart_filter') }
  let(:cart) { live_mount('cart_list', connection: filter.connection) }

  it 'shows the latest value when the component re-renders for its own reasons' do
    cart.perform(:add_item)
    filter.perform(:set_filter)

    expect(filter.rendered).to have_css('[data-testid="badge"]', text: '1')
    expect(filter.rendered).to have_css('[data-testid="badge-method"]', text: '1')
  end

  it 'shows its own write made alongside a reactive change' do
    filter.perform(:add_and_filter)

    expect(filter.rendered).to have_css('[data-testid="badge"]', text: '1')
    expect(filter.rendered).to have_css('[data-testid="badge-method"]', text: '1')
  end

  it 'does not re-render when only the shared variable changes' do
    cart
    filter.clear_broadcasts

    cart.perform(:add_item)
    filter.perform(:add_only)

    expect(filter.broadcasts(:_refresh)).to be_empty
  end

  it 're-renders a component that declares the same name with reactive' do
    cart

    filter.perform(:add_only)

    expect(cart.rendered).to have_css('li', exact_text: 'quiet')
  end
end
