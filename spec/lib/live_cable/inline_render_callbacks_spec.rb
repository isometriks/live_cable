# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Render callbacks on a child rendered by its parent' do
  include LiveCable::Testing

  it "runs them for the parent's first render" do
    parent = live_mount('doubling_parent')

    expect(parent.rendered).to have_css('[data-testid="doubled"]', exact_text: '4')
  end

  it 'runs them each time the parent renders the child again' do
    parent = live_mount('doubling_parent')

    parent.perform(:relabel_and_add)

    expect(parent.rendered).to have_css('[data-testid="doubled"]', exact_text: '24')
  end

  it "doesn't run them when the parent skips the child's part" do
    parent = live_mount('doubling_parent')
    child = parent.connection.get_component('doubling_child/child')

    expect { parent.perform(:annotate) }.not_to change(child, :render_count).from(1)
    expect(parent.rendered).to have_css('p', exact_text: 'noted')
  end

  it "sends an error from a failing child callback through the parent's error handling" do
    allow(Rails.error).to receive(:report)
    parent = live_mount('doubling_parent', raise_errors: false)

    parent.perform(:explode)

    expect(parent.broadcasts.last.keys).to eq([:_error])
    expect(parent.broadcasts.last[:_error]).to include('child before_render failed')
  end
end
