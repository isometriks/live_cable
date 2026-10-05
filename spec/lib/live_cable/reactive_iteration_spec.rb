# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Iterating reactive collections in templates' do
  include LiveCable::Testing

  it 'renders and re-renders items.each.with_index' do
    list = live_mount('numbered_list')

    list.perform(:add)

    expect(list.rendered).to have_css('[data-testid="item-1"]', text: '1. a')
    expect(list.rendered).to have_css('[data-testid="item-2"]', text: '2. b')
  end

  it 'tracks changes made through items.each.with_index in an action' do
    list = live_mount('numbered_list')

    list.perform(:number)

    expect(list.rendered).to have_css('[data-testid="item-1"]', text: '1. a1')
  end
end
