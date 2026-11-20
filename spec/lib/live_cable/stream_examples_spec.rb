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

  describe 'a notification from a broadcast' do
    let(:inbox) { live_mount('streams/inbox') }

    def message(id, text) = { 'id' => id, 'text' => text }

    it 'sends one op as no reply, with the event in the same frame' do
      inbox.clear_broadcasts

      inbox.receive_stream('inbox', message(1, 'hi'))

      frame = inbox.broadcasts.sole
      expect(frame[:_reply]).to be(false)
      expect(frame[:_events]).to eq([{ name: 'inbox:message-received', detail: { 'id' => 1 }, window: false }])
      expect(frame[:_refresh][:p].compact.size).to eq(1)
      expect(ops(inbox, :messages)).to eq([['a', 'message-1', ['hi']]])
    end

    it 'keeps the rows in rendered across clear_broadcasts' do
      inbox.receive_stream('inbox', message(1, 'hello'))
      inbox.clear_broadcasts

      inbox.receive_stream('inbox', message(2, 'world'))

      expect(inbox.rendered).to have_css('[data-testid="inbox"] li', count: 2)
      expect(inbox.stream_ids(:messages)).to eq(%w[message-1 message-2])
    end

    it 'shows a duplicate delivery once' do
      inbox.receive_stream('inbox', message(1, 'hello'))
      inbox.receive_stream('inbox', message(1, 'hello'))

      expect(inbox.rendered).to have_css('li', count: 1)
      expect(inbox.dispatched_events.size).to eq(2)
    end
  end

  describe 'an event after an insert from an action' do
    let(:feed) { live_mount('streams/event_feed') }

    it 'sends the row op as the reply, with the event in the same frame' do
      feed.clear_broadcasts

      feed.perform(:add_item)

      frame = feed.broadcasts.sole
      expect(frame[:_reply]).to be(true)
      expect(frame[:_events]).to eq([{ name: 'event-test:item-added', detail: { 'count' => 1 }, window: false }])
      expect(ops(feed, :items)).to eq([['a', 'item-1', ['1']]])
    end
  end
end
