# frozen_string_literal: true

require 'rails_helper'

# The dummy app's stream_from examples, written as collection streams
RSpec.describe 'Collection stream examples' do
  include LiveCable::Testing

  def ops(component, name) = component.stream_ops(name)

  describe 'a room switch' do
    before do
      RoomHistory.reset!
      RoomHistory.add(1, 'one')
      RoomHistory.add(2, 'two')
    end

    let(:lobby) { live_mount('streams/lobby') }

    def texts = lobby.rendered.all('li').map(&:text)

    it "renders the room's history, and appends each broadcast as one op" do
      expect(texts).to eq(['one'])
      lobby.clear_broadcasts

      lobby.receive_stream('lobby_1', RoomHistory.add(1, 'hello'))

      expect(ops(lobby, :messages)).to eq([['a', 'message-3', ['hello']]])
      expect(lobby.broadcasts(:_refresh).sole[:_refresh][:p].compact.size).to eq(1)
      expect(texts).to eq(%w[one hello])
    end

    it "refills from the new room's history and follows its broadcasts" do
      lobby.perform(:switch_room, room_id: 2)

      expect(lobby.rendered).to have_css('h2', text: 'Room 2')
      expect(texts).to eq(['two'])

      lobby.receive_stream('lobby_2', RoomHistory.add(2, 'hello'))

      expect(texts).to eq(%w[two hello])
    end

    it 'queues nothing for a broadcast ActionCable delivers to the old room after the switch' do
      queued = lobby.channel.streams.fetch('lobby_1')[:callback]
      lobby.perform(:switch_room, room_id: 2)
      lobby.clear_broadcasts

      queued.call(RoomHistory.add(1, 'late'))

      expect(lobby.broadcasts).to be_empty
      expect(texts).to eq(['two'])
    end

    it 'queues nothing for an old-room callback that waited on the lock during the switch' do
      queued = lobby.channel.streams.fetch('lobby_1')[:callback]
      waiting = nil

      lobby.connection.synchronize do
        waiting = Thread.new { queued.call(RoomHistory.add(1, 'late')) }
        Thread.pass until waiting.stop?
        lobby.perform(:switch_room, room_id: 2)
      end
      waiting.join

      expect(texts).to eq(['two'])
    end

    it 'sends the heading and the refilled list in one frame' do
      lobby.clear_broadcasts

      lobby.perform(:switch_room, room_id: 2)

      expect(lobby.broadcasts(:_refresh).size).to eq(1)
      expect(ops(lobby, :messages)).to eq([['reset', ['message-2']]])
      expect(texts).to eq(['two'])
    end
  end
end
