# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LiveCable::Component::Streaming do
  include LiveCable::Testing

  def mount_counter(**defaults)
    live_mount('counter', **defaults).tap do |counter|
      counter.component.send(:stream_from, 'counts') do |count|
        counter.count = count unless count.nil?
      end
    end
  end

  def refreshed_parts(component)
    component.broadcasts(:_refresh).map { |broadcast| broadcast[:_refresh][:p].compact }
  end

  describe 'rendering a callback' do
    it 'does not re-send what an earlier message changed when the callback changes nothing' do
      counter = mount_counter
      counter.set_reactive(:step, 5)
      counter.clear_broadcasts

      counter.receive_stream('counts', nil)

      expect(counter.broadcasts(:_refresh)).to be_empty
    end

    it 're-sends only the parts the callback changed' do
      counter = mount_counter
      counter.set_reactive(:step, 5)
      counter.clear_broadcasts

      counter.receive_stream('counts', 3)

      expect(refreshed_parts(counter)).to eq([['3']])
    end

    it 'does not re-send the defaults applied at mount' do
      counter = mount_counter(step: 5)
      counter.clear_broadcasts

      counter.receive_stream('counts', nil)

      expect(counter.broadcasts(:_refresh)).to be_empty
    end

    it 'does not re-render another component on the connection' do
      counter = live_mount('counter')
      stream = live_mount('stream_test', connection: counter.connection)
      counter.set_reactive(:step, 5)
      counter.clear_broadcasts

      stream.receive_stream('test_messages', { text: 'hi' })

      expect(counter.broadcasts(:_refresh)).to be_empty
      expect(stream.rendered).to have_css('li', text: 'hi')
    end
  end

  describe 'starting a stream again under the same name' do
    let(:room) { live_mount('room') }

    # ActionCable subscribes another handler for each stream_from, and within
    # one job subscribes it after a stop that should have removed it
    it 'keeps the ActionCable stream it already has' do
      allow(room.channel).to receive(:stream_from).and_call_original
      allow(room.channel).to receive(:stop_stream_from).and_call_original

      room.component.send(:join_room)

      expect(room.channel).not_to have_received(:stream_from)
      expect(room.channel).not_to have_received(:stop_stream_from)
    end

    it 'runs the newer callback' do
      notices = []
      room.component.send(:stream_from, 'room_1') { |notice| notices << notice }

      room.receive_stream('room_1', 'hi')

      expect(notices).to eq(['hi'])
      expect(room.messages).to be_empty
    end

    it 'runs nothing from the stream a call with another coder replaced' do
      replaced = room.channel.streams.fetch('room_1')[:callback]
      notices = []
      room.component.send(:stream_from, 'room_1') { |notice| notices << notice }
      room.clear_broadcasts

      replaced.call({ 'text' => 'hi' })

      expect(notices).to be_empty
      expect(room.messages).to be_empty
      expect(room.broadcasts).to be_empty
    end
  end

  describe 'a callback that raises' do
    before { allow(Rails.error).to receive(:report) }

    it 'still renders the other components it changed' do
      failing = live_mount('shared_counter', id: 'failing', raise_errors: false)
      other = live_mount('shared_counter', id: 'other', connection: failing.connection)
      failing.component.send(:stream_from, 'bumps') do
        failing.bump
        raise 'callback failed'
      end

      failing.receive_stream('bumps', nil)

      expect(failing.broadcasts(:_error)).not_to be_empty
      expect(other.rendered).to have_css('[data-testid="total-other"]', text: '1')
    end

    it 'sends an _error for a NotImplementedError' do
      counter = live_mount('counter', raise_errors: false)
      counter.component.send(:stream_from, 'counts') { raise NotImplementedError, 'abstract' }

      expect { counter.receive_stream('counts', nil) }.not_to raise_error

      expect(counter.broadcasts.last[:_error]).to include('abstract')
    end
  end

  describe 'a callback for a stopped stream' do
    let(:room) { live_mount('room') }
    let!(:queued) { room.channel.streams.fetch('room_1')[:callback] }

    it 'is ignored when ActionCable runs it after the room switched' do
      room.perform(:switch_room, room_id: 2)
      room.clear_broadcasts

      queued.call('text' => 'late')

      expect(room.messages).to be_empty
      expect(room.broadcasts).to be_empty
    end

    it 'is ignored when it was waiting on the lock while the room switched' do
      waiting = nil

      room.connection.synchronize do
        waiting = Thread.new { queued.call('text' => 'late') }
        Thread.pass until waiting.stop?
        room.perform(:switch_room, room_id: 2)
      end
      waiting.join

      expect(room.messages).to be_empty
    end

    it 'is ignored when ActionCable runs it after stop_stream' do
      room.perform(:leave)
      room.clear_broadcasts

      queued.call('text' => 'late')

      expect(room.messages).to be_empty
      expect(room.broadcasts).to be_empty
    end

    it 'still runs when the stream was stopped and started again' do
      room.perform(:switch_room, room_id: 1)

      queued.call('text' => 'hello')

      expect(room.messages).to eq(['hello'])
    end

    it 'leaves the other streams running' do
      notices = []
      room.component.send(:stream_from, 'notices') { |notice| notices << notice }

      room.perform(:switch_room, room_id: 2)
      room.receive_stream('notices', 'hi')
      room.receive_stream('room_2', { text: 'hello' })

      expect(notices).to eq(['hi'])
      expect(room.messages).to eq(['hello'])
    end
  end

  describe 'a callback after disconnect' do
    let(:received) { [] }
    let(:counter) { live_mount('counter') }
    let!(:callback) do
      counter.component.send(:stream_from, 'counts') { |count| received << count }
      counter.channel.streams.fetch('counts')[:callback]
    end

    it 'is ignored when ActionCable runs it after the stream was stopped' do
      counter.unmount

      expect { callback.call(3) }.not_to raise_error
      expect(received).to be_empty
    end

    it 'is ignored when it was waiting on the lock while the component disconnected' do
      waiting = nil

      counter.connection.synchronize do
        waiting = Thread.new { callback.call(3) }
        Thread.pass until waiting.stop?
        counter.unmount
      end

      expect { waiting.join }.not_to raise_error
      expect(received).to be_empty
    end
  end
end
