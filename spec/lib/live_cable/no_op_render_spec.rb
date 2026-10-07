# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Renders that change nothing on the page' do
  include LiveCable::Testing

  it 'are not broadcast, and the message is answered with an _ack' do
    component = live_mount('hidden_var')
    component.clear_broadcasts

    # :hidden is never rendered by the template
    component.perform(:bump_hidden)

    expect(component.broadcasts).to eq([{ _ack: true }])
    expect(component.hidden).to eq(1)
  end

  it 'are not broadcast when a group assigns a local no later tag reads' do
    component = live_mount('unread_locals')
    component.clear_broadcasts

    component.perform(:bump_hidden)

    expect(component.broadcasts).to eq([{ _ack: true }])
  end

  it 'still answer with a _refresh when a part reads a local an earlier tag assigns' do
    component = live_mount('local_vars')
    component.clear_broadcasts

    component.perform(:bump_hidden)

    expect(component.broadcasts(:_refresh).size).to eq(1)
    expect(component.broadcasts(:_ack)).to be_empty
  end

  it 'still run their render callbacks' do
    component = live_mount('hidden_var')

    expect { component.perform(:bump_hidden) }.to change(component, :render_count).by(1)
  end

  it 'are not broadcast by a component that shares the changed variable without showing it' do
    counter = live_mount('shared_counter')
    component = live_mount('hidden_var', connection: counter.connection)
    component.clear_broadcasts

    counter.perform(:bump)

    expect(component.broadcasts).to be_empty
    expect(component.render_count).to eq(2)
  end

  it 'still broadcast a _refresh, as the reply, when the output changes' do
    component = live_mount('hidden_var')
    component.clear_broadcasts

    component.perform(:bump_shown)

    expect(component.broadcasts(:_refresh).map { |b| b[:_reply] }).to eq([true])
    expect(component.broadcasts(:_ack)).to be_empty
    expect(component.rendered).to have_css('[data-testid="shown"]', text: '1')
  end

  it 'still deliver the events they queued' do
    component = live_mount('hidden_var')
    component.clear_broadcasts

    component.perform(:bump_hidden_with_event)

    expect(component.broadcasts(:_refresh)).to be_empty
    expect(component.dispatched_events).to eq([{ name: 'hidden:changed', detail: {}, window: false }])
  end
end
