# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LiveCable::ActionCableConnection do
  let(:connection) { ApplicationCable::Connection.new(ActionCable.server, Rack::MockRequest.env_for('/cable')) }

  it 'gives every socket a LiveCable::Connection without the application declaring one' do
    expect(connection.live_connection).to be_a(LiveCable::Connection)
    expect(connection.live_connection).to equal(connection.live_connection)
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
