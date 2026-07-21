# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Server-dispatched events' do
  include LiveCable::Testing

  it 'attaches events to the render broadcast when state changes' do
    component = live_mount('event_test')
    component.clear_broadcasts

    component.perform(:add_item)

    refresh = component.broadcasts(:_refresh).first
    expect(refresh[:_events]).to eq(
      [{ name: 'event-test:item-added', detail: { 'count' => 1 }, window: false }]
    )
  end

  it 'broadcasts events on their own when nothing re-renders' do
    component = live_mount('event_test')
    component.clear_broadcasts

    component.perform(:ping)

    expect(component.broadcasts(:_refresh)).to be_empty
    expect(component.dispatched_events).to eq(
      [{ name: 'event-test:pinged', detail: {}, window: false }]
    )

    # The ack still arrives so the client's loading state clears
    expect(component.broadcasts(:_ack).size).to eq(1)
  end

  it 'marks events targeted at window' do
    component = live_mount('event_test')

    component.perform(:ping_window)

    expect(component.dispatched_events).to eq(
      [{ name: 'event-test:window-pinged', detail: {}, window: true }]
    )
  end

  it 'collects events across multiple actions in order' do
    component = live_mount('event_test')

    component.perform(:add_item)
    component.perform(:ping)
    component.perform(:add_item)

    expect(component.dispatched_events.map { |event| event[:name] }).to eq(
      ['event-test:item-added', 'event-test:pinged', 'event-test:item-added']
    )
  end

  it 'delivers events dispatched from stream callbacks' do
    stream = live_mount('stream_test')
    stream.clear_broadcasts

    stream.receive_stream('test_messages', { text: 'hi' })

    expect(stream.dispatched_events).to eq(
      [{ name: 'stream-test:message-received', detail: { 'text' => 'hi' }, window: false }]
    )
  end
end
