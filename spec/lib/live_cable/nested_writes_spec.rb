# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Changes through aliased mutators and nested reads' do
  include LiveCable::Testing

  it 're-renders after a change to an element found with detect' do
    component = live_mount('nested_writes')

    component.perform(:finish_first)

    expect(component.broadcasts(:_ack)).to be_empty
    expect(component.rendered).to have_css('[data-testid="done"]', text: '1')
  end

  it 're-renders after a change to a value yielded by Hash#each' do
    component = live_mount('nested_writes')

    component.perform(:add_to_lists)

    expect(component.broadcasts(:_ack)).to be_empty
    expect(component.rendered).to have_css('[data-testid="open"]', text: '1')
  end

  it 're-renders after append' do
    component = live_mount('nested_writes')

    component.perform(:append_tag)

    expect(component.broadcasts(:_ack)).to be_empty
    expect(component.rendered).to have_css('[data-testid="tags"]', text: 'ruby,rails')
  end
end
