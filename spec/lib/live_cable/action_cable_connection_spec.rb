# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LiveCable::ActionCableConnection do
  let(:connection) { ApplicationCable::Connection.new(ActionCable.server, Rack::MockRequest.env_for('/cable')) }

  it 'gives every socket a LiveCable::Connection without the application declaring one' do
    expect(connection.live_connection).to be_a(LiveCable::Connection)
    expect(connection.live_connection).to equal(connection.live_connection)
  end

  it 'builds a single LiveCable::Connection when two subscribes ask for it at once' do
    building = Queue.new
    allow(LiveCable::Connection).to receive(:new).and_wrap_original do |original, *args|
      building << true
      sleep 0.1
      original.call(*args)
    end

    first = Thread.new { connection.live_connection }
    building.pop
    second = Thread.new { connection.live_connection }

    expect(first.value).to equal(second.value)
  end

  describe 'commands from the client' do
    let(:jobs) { [] }
    let(:handled) { [] }

    before do
      allow(connection).to receive(:send_async) { |method, *args| jobs << [method, args] }
      websocket = instance_double(ActionCable::Connection::WebSocket, alive?: true)
      allow(connection).to receive(:websocket).and_return(websocket)
      allow(connection).to receive(:handle_channel_command) { |payload| handled << payload['data'] }
    end

    def frame(channel, data)
      { command: 'message', identifier: { channel: channel, id: 'x' }.to_json, data: data }.to_json
    end

    def run_jobs(order)
      order.each { |method, args| connection.send(method, *args) }
    end

    it 'runs LiveChannel commands in the order they arrived, whichever job starts first' do
      %w[h he hel].each { |value| connection.receive(frame('LiveChannel', value)) }

      run_jobs(jobs.reverse)

      expect(handled).to eq(%w[h he hel])
    end

    it 'runs them one at a time when their jobs start together' do
      %w[first second].each { |value| connection.receive(frame('LiveChannel', value)) }
      started = Queue.new
      release = Queue.new
      allow(connection).to receive(:handle_channel_command) do |payload|
        started << payload['data']
        release.pop
        handled << payload['data']
      end

      threads = jobs.reverse.map { |job| Thread.new { run_jobs([job]) } }
      expect(started.pop).to eq('first')
      sleep 0.05
      expect(started).to be_empty

      2.times { release << true }
      threads.each(&:join)

      expect(handled).to eq(%w[first second])
    end

    it 'leaves other channels\' commands to ActionCable' do
      connection.receive(frame('ChatChannel', 'LiveChannel'))

      expect(jobs).to eq([[:dispatch_websocket_message, [frame('ChatChannel', 'LiveChannel')]]])
    end

    it 'leaves a frame it cannot read to ActionCable' do
      connection.receive('LiveChannel?')

      expect(jobs).to eq([[:dispatch_websocket_message, ['LiveChannel?']]])
    end
  end

  it 'declares no identifier of its own' do
    expect(ApplicationCable::Connection.identifiers).not_to include(:live_connection)
  end

  it 'leaves remote disconnection by the application\'s own identifiers possible' do
    # Every declared identifier has to be supplied to address a remote
    # connection, and a per-socket object could never be. The dummy app
    # happens to identify by current_user; any identifier, or none, would do.
    expect { ActionCable.server.remote_connections.where(current_user: 'guest') }.not_to raise_error
  end
end
