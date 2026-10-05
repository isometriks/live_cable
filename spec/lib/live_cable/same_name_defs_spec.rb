# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'A component method that shares its name with a def self.x' do
  include LiveCable::Testing

  it 're-renders a part calling the instance method when its dependencies change' do
    component = live_mount('same_name_defs')

    component.perform(:increment)

    expect(component.rendered).to have_css('[data-testid="title"]', exact_text: 'title=1')
  end
end
