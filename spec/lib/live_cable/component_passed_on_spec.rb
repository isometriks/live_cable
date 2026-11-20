# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'A tag that passes component on' do
  include LiveCable::Testing

  it 're-renders when the component changes, whatever it passes component to' do
    component = live_mount('passes_component')

    component.perform(:increment)

    %w[partial then map local].each do |testid|
      expect(component.rendered).to have_css("[data-testid='#{testid}']", exact_text: '1')
    end
  end
end
