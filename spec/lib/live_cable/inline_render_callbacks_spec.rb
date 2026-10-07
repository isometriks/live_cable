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

  it 'runs them once for a grandchild that changed along with its grandparent' do
    grandparent = live_mount('doubling_grandparent')
    child = grandparent.connection.get_component('doubling_child/child')

    expect { grandparent.perform(:add) }.to change(child, :render_count).by(1)
  end

  it "still runs them for a grandchild whose parent's render halted" do
    grandparent = live_mount('doubling_grandparent')
    child = grandparent.connection.get_component('doubling_child/child')

    expect { grandparent.perform(:overflow) }.to change(child, :render_count).by(1)
  end

  it "still runs them for a child whose top-level parent's render halted" do
    middle = live_mount('doubling_middle')
    child = middle.connection.get_component('doubling_child/child')

    expect { middle.perform(:overflow) }.to change(child, :render_count).by(1)
  end

  it 'runs them once for a child whose parent was mounted again' do
    first = live_mount('doubling_parent')
    connection = first.connection
    child = connection.get_component('doubling_child/child')
    first.unmount
    parent = live_mount('doubling_parent', connection:)

    expect { parent.perform(:relabel_and_add) }.to change(child, :render_count).by(1)
  end

  it 'runs them once per render for a top-level component' do
    component = live_mount('doubling_child')
    expect(component.render_count).to eq(1)

    parent = live_mount('doubling_parent', connection: component.connection)

    expect { parent.perform(:relabel_and_add) }.to change(component, :render_count).by(1)
  end

  it 'keeps what the child last rendered when one of them halts' do
    parent = live_mount('doubling_parent')

    parent.perform(:halt)

    expect(parent.rendered).to have_css('[data-testid="doubled"]', exact_text: '4')
  end

  it "sends an error from a failing child callback through the parent's error handling" do
    allow(Rails.error).to receive(:report)
    parent = live_mount('doubling_parent', raise_errors: false)

    parent.perform(:explode)

    expect(parent.broadcasts.last.keys).to eq([:_error])
    expect(parent.broadcasts.last[:_error]).to include('child before_render failed')
    expect(Rails.error).to have_received(:report).once
  end
end
