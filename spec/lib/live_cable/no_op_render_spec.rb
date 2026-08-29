# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'No-op render suppression' do
  include LiveCable::Testing

  it 'does not broadcast a _refresh when nothing in the output changed' do
    component = live_mount('hidden_var')
    component.clear_broadcasts

    # :hidden is never rendered by the template
    component.perform(:bump_hidden)

    expect(component.broadcasts(:_refresh)).to be_empty
    # The client still gets an ack so its loading state clears
    expect(component.broadcasts(:_ack).size).to eq(1)
    expect(component.hidden).to eq(1)
  end

  it 'still broadcasts a _refresh when the output changes' do
    component = live_mount('hidden_var')
    component.clear_broadcasts

    component.perform(:bump_shown)

    refreshes = component.broadcasts(:_refresh)
    expect(refreshes.size).to eq(1)
    expect(refreshes.first[:_refresh][:p]).to include('1')
    expect(component.broadcasts(:_ack)).to be_empty
  end

  it 'delivers events even when the render is a no-op' do
    component = live_mount('hidden_var')
    component.clear_broadcasts

    component.perform(:bump_hidden_with_event)

    expect(component.broadcasts(:_refresh)).to be_empty
    expect(component.dispatched_events).to eq([{ name: 'hidden:changed', detail: {}, window: false }])
  end
end
