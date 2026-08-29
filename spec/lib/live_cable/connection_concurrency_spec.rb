# frozen_string_literal: true

require 'rails_helper'
require 'action_dispatch/testing/test_request'

# Exercises the connection lock added so a single Connection - shared by every
# component subscription on one ActionCable socket - can be driven from
# multiple worker threads without corrupting its shared @components /
# @containers state.
RSpec.describe 'Connection concurrency' do
  def build_connection
    LiveCable::Connection.new(ActionDispatch::TestRequest.create('rack.session' => {}))
  end

  it 'exposes a re-entrant synchronize (nested calls do not deadlock)' do
    connection = build_connection

    result = connection.synchronize do
      connection.synchronize { :ok }
    end

    expect(result).to eq(:ok)
  end

  it 'survives concurrent add/broadcast/remove without raising or corrupting state' do
    connection = build_connection
    errors = Queue.new
    thread_count = 8
    per_thread = 40

    threads = Array.new(thread_count) do |t|
      Thread.new do
        per_thread.times do |i|
          component = Live::Counter.new("c-#{t}-#{i}")
          channel = LiveCable::Testing::TestChannel.new
          connection.add_component(component)
          component.connect(channel)
          connection.synchronize { connection.set(component.live_id, :count, i) }
          connection.broadcast_changeset
          component.disconnect # calls remove_component
        end
      rescue StandardError => e
        errors << e
      end
    end

    threads.each(&:join)

    expect(errors).to be_empty, -> { "concurrent access raised: #{errors.pop.inspect}" }

    # Every component disconnected, so the connection should be drained.
    remaining = connection.instance_variable_get(:@components)
    expect(remaining).to be_empty
  end
end
