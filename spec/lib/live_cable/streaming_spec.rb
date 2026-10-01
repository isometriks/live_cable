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
