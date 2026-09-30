# frozen_string_literal: true

require 'rails_helper'
require 'action_dispatch/testing/test_request'

# One Connection is shared by every component on a socket, and ActionCable
# runs that socket's messages and stream callbacks as separate jobs on a
# shared worker pool. These drive a connection from several threads at once.
RSpec.describe 'Connection concurrency' do
  let(:connection) { LiveCable::Connection.new(ActionDispatch::TestRequest.create('rack.session' => {})) }

  it 'has a re-entrant lock, so nested calls on one thread do not deadlock' do
    result = connection.synchronize do
      connection.synchronize { :ok }
    end

    expect(result).to eq(:ok)
  end

  # The field report's duplicated invoice line: an action saves a record
  # (whose after_commit broadcasts to the component's own stream), then pushes
  # it onto a reactive array. A stream callback that reloads the array from the
  # database, landing between the save and the push, loaded the record and
  # then had it pushed a second time.
  it 'does not let a stream callback land between an action and the rest of it' do
    store = [] # stands in for the database
    wrote = Queue.new

    component_class = Class.new(LiveCable::Component) do
      def self.name
        'Live::ConcurrencyExample'
      end

      reactive :items, -> { [] }
      actions :add

      define_method(:add) do
        store << 'line'  # the save, which broadcasts
        wrote << true
        sleep 0.2        # the gap before the push
        items << 'line'  # the push
      end
    end

    component = component_class.new('c1')
    channel = LiveCable::Testing::TestChannel.new
    connection.add_component(component)
    component.connect(channel)
    # No template for this anonymous class; rendering isn't under test
    allow(component).to receive(:broadcast_render)
    component.send(:stream_from, 'store') { component.items = store.dup }

    action = Thread.new { connection.receive(component, 'messages' => [{ '_action' => 'add' }]) }
    wrote.pop
    channel.broadcast_to('store', {}) # the after_commit broadcast arriving on another worker
    action.join

    expect(component.items.to_a).to eq(['line'])
  end

  it 'survives concurrent add, broadcast and remove without raising or losing track' do
    errors = Queue.new

    threads = Array.new(8) do |t|
      Thread.new do
        40.times do |i|
          component = Live::Counter.new("c-#{t}-#{i}")
          connection.add_component(component)
          component.connect(LiveCable::Testing::TestChannel.new)
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
    expect(connection.send(:components)).to be_empty
  end
end
