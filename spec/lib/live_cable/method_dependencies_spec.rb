# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Re-rendering parts that call component methods' do
  include LiveCable::Testing

  it 're-renders them when the component has no source file to analyze' do
    allow(Object).to receive(:const_source_location).and_call_original
    allow(Object).to receive(:const_source_location).with('Live::RenderComponent').and_return(nil)
    allow(Live::RenderComponent).to receive(:method_dependencies_analyzer).
      and_return(LiveCable::Rendering::MethodAnalyzer.new(Live::RenderComponent))
    component = live_mount('render_component')

    component.perform(:increment)

    expect(component.rendered).to have_css('[data-testid="badge"]', text: 'Count: 2')
  end
end
