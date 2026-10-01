# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Names called on component or self in a template' do
  include LiveCable::Testing

  let(:component) { live_mount('receiver_calls') }

  it 're-renders component.x and self.x when x changes' do
    component.perform(:restyle)

    expect(component.rendered).to have_css('[data-testid="component"]', text: 'dark')
    expect(component.rendered).to have_css('[data-testid="self"]', text: 'dark')
  end

  it 'resolves self.x to the component when Kernel also defines x' do
    expect(component.rendered).to have_css('[data-testid="open"]', text: 'false')

    component.perform(:toggle)

    expect(component.rendered).to have_css('[data-testid="open"]', text: 'true')
  end
end
