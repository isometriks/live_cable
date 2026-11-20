# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Work for a component that has not subscribed yet' do
  include LiveCable::Testing

  def counter_on(connection, id)
    live_mount('shared_counter', id:, connection:)
  end

  describe 'an inline child' do
    it 'is not rendered while it has no channel' do
      host = live_mount('counter_host')
      child = host.connection.get_component('shared_counter/inline')
      other = counter_on(host.connection, 'other')
      allow(child).to receive(:broadcast_render).and_call_original

      expect { other.perform(:bump) }.not_to(change { child.send(:static_sent) })
      expect(child).not_to have_received(:broadcast_render)
    end

    it 'sends what changed when it subscribes' do
      host = live_mount('counter_host')
      other = counter_on(host.connection, 'other')
      other.perform(:bump)

      child = host.subscribe_child('shared_counter/inline')

      frame = child.broadcasts(:_refresh).sole
      expect(frame).to include(_subscribed: true, _reply: false)
      expect(frame[:_refresh][:p].compact).to eq(['1'])
    end

    it 'sends what changed when it subscribes after unrelated updates' do
      host = live_mount('counter_host')
      stream = live_mount('stream_test', connection: host.connection)
      other = counter_on(host.connection, 'other')
      other.perform(:bump)
      host.perform(:rename)
      stream.receive_stream('test_messages', { text: 'hello' })

      child = host.subscribe_child('shared_counter/inline')

      expect(child.broadcasts(:_refresh).sole[:_refresh][:p].compact).to eq(['1'])
    end

    it 'sends only its status when nothing changed since its parent rendered it' do
      parent = live_mount('parent')

      child = parent.subscribe_child('child/child-0')

      expect(child.broadcasts).to eq([{ _status: 'subscribed', id: 'child/child-0', _subscribed: true }])
      expect(child.renders).to eq(1)
    end

    it 'sends its status when a callback halts the render it subscribes with' do
      host = live_mount('halting_host')

      child = host.subscribe_child('halting_sharer/child')

      expect(child.broadcasts).to eq([{ _status: 'subscribed', id: 'halting_sharer/child', _subscribed: true }])
    end

    it 'leaves a shared change for the children of a halted subscribe render' do
      host = live_mount('halting_host')
      host.subscribe_child('halting_sharer/child')

      badge = host.subscribe_child('total_badge/inner')

      expect(badge.broadcasts(:_refresh).sole[:_refresh][:p].compact).to eq(['1'])
    end

    it 'cannot be subscribed before a parent renders it' do
      parent = live_mount('parent')

      expect { parent.subscribe_child('child/child-9') }.to raise_error(LiveCable::Error, %r{child/child-9})
    end
  end

  describe 'live_mount' do
    it 'connects the component holding the connection lock' do
      probe = live_mount('lock_probe')

      expect(probe.locked_on_connect).to be(true)
    end

    it 'sends the status of a component whose first render a callback halts' do
      paused = live_mount('pausable', paused: true)

      expect(paused.broadcasts).to eq([{ _status: 'subscribed', id: paused.live_id, _subscribed: true }])
    end

    it 'still returns a component whose first render failed' do
      failing = live_mount('failing_initial', raise_errors: false)

      expect(failing.broadcasts.map(&:keys)).to eq([[:_error]])
    end
  end
end
