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

  it 'keeps events queued for a component with no channel and delivers them on subscribe' do
    require 'action_dispatch/testing/test_request'
    connection = LiveCable::Connection.new(
      ActionDispatch::TestRequest.create('rack.session' => {})
    )

    # A component added to the connection but not yet connected has no channel,
    # like a child rendered inline by a parent before its own subscription.
    component = Live::EventTest.new('detached')
    connection.add_component(component)
    component.send(:dispatch_event, 'event-test:early', {})

    connection.broadcast_changeset

    # Not dropped - still queued because there was no channel to deliver on
    expect(component.send(:pending_events)).not_to be_empty

    # Once it connects, broadcast_subscribe flushes the queued events
    channel = LiveCable::Testing::TestChannel.new
    component.connect(channel)
    component.broadcast_subscribe

    delivered = channel.transmissions.select { |t| t.key?(:_events) }.flat_map { |t| t[:_events] }
    expect(delivered).to eq([{ name: 'event-test:early', detail: {}, window: false }])
  end
end
