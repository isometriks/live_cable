# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'One reply per message batch' do
  include LiveCable::Testing

  def replies(transmissions)
    transmissions.select { |frame| frame[:_ack] || frame[:_error] || frame[:_reply] == true }
  end

  def mount_tree(raise_errors: true)
    parent = live_mount('reply_parent', raise_errors:)
    child = parent.connection.get_component('reply_child/a')
    channel = LiveCable::Testing::TestChannel.new
    child.connect(channel)
    parent.clear_broadcasts
    [parent, child, channel]
  end

  def send_batch(parent, child, *actions)
    messages = actions.map { |action| { '_action' => action.to_s, 'params' => '' } }
    parent.connection.receive(child, { 'messages' => messages })
  end

  it 'answers a child action that renders only the child with its own refresh' do
    parent, child, channel = mount_tree

    send_batch(parent, child, :own)

    expect(replies(channel.transmissions)).to eq([channel.transmissions.find { it[:_refresh] }])
    expect(channel.transmissions.sole).to include(_reply: true)
    expect(parent.broadcasts).to be_empty
  end

  it 'answers a child action that renders only the parent with a bare ack' do
    parent, child, channel = mount_tree

    send_batch(parent, child, :bump_shared)

    expect(parent.broadcasts(:_refresh).sole).to include(_reply: false)
    expect(channel.transmissions).to eq([{ _ack: true }])
  end

  it 'answers a grandchild whose render rides in its grandparent frame with one rendered ack' do
    grand = live_mount('reply_grand')
    child = grand.connection.get_component('reply_child/a')
    channel = LiveCable::Testing::TestChannel.new
    child.connect(channel)
    grand.clear_broadcasts

    send_batch(grand, child, :bump_both)

    expect(grand.broadcasts(:_refresh).sole[:_refresh][:c].keys).to include('reply_parent/p', 'reply_child/a')
    expect(channel.transmissions).to eq([{ _ack: true, _rendered: true }])
  end

  it 'answers a child action whose render rides inline in the parent with one rendered ack' do
    parent, child, channel = mount_tree

    send_batch(parent, child, :bump_both)

    expect(parent.broadcasts(:_refresh).sole[:_refresh][:c]).to have_key('reply_child/a')
    expect(channel.transmissions).to eq([{ _ack: true, _rendered: true }])
  end

  it 'answers an action that raises with one _error' do
    parent, child, channel = mount_tree(raise_errors: false)

    send_batch(parent, child, :raise_plain)

    expect(replies(channel.transmissions).size).to eq(1)
    expect(channel.transmissions.sole).to have_key(:_error)
  end

  it 'answers an action whose rescue_from changes nothing with an ack' do
    parent, child, channel = mount_tree(raise_errors: false)

    send_batch(parent, child, :raise_handled_noop)

    expect(channel.transmissions).to eq([{ _ack: true }])
  end

  it 'answers an action whose rescue_from changes state with its refresh' do
    parent, child, channel = mount_tree(raise_errors: false)

    send_batch(parent, child, :raise_handled_change)

    expect(replies(channel.transmissions).size).to eq(1)
    expect(channel.transmissions.sole).to include(_reply: true)
  end

  it 'answers a before_dispatch halt with an ack' do
    parent, child, channel = mount_tree
    child.halt = true
    parent.connection.reset_changeset

    send_batch(parent, child, :halted)

    expect(channel.transmissions).to eq([{ _ack: true }])
    expect(child.count).to eq(0)
  end

  it 'answers a batch in which one message fails with one _error and nothing that counts as a reply after it' do
    parent, child, channel = mount_tree(raise_errors: false)

    send_batch(parent, child, :own, :raise_plain, :own)

    expect(replies(channel.transmissions).size).to eq(1)
    expect(channel.transmissions.map(&:keys).flatten).to include(:_error)
  end

  it 'answers an action that stops its parent rendering it' do
    parent, child, channel = mount_tree

    send_batch(parent, child, :hide_me)

    statuses = channel.transmissions
    expect(statuses.first).to eq({ _status: 'destroy' })
    expect(replies(statuses).size).to be <= 1
  end

  it 'answers an action whose change makes the parent render raise' do
    parent, child, channel = mount_tree(raise_errors: false)

    send_batch(parent, child, :explode_parent)

    expect(parent.broadcasts(:_error).size).to eq(1)
    expect(replies(channel.transmissions).size).to be <= 1
  end

  it 'gives a render from another thread that takes the lock no reply' do
    parent, child, channel = mount_tree

    send_batch(parent, child, :thread_write)
    child.join_thread

    expect(replies(channel.transmissions).size).to eq(1)
    expect(channel.transmissions.last).to include(_reply: false)
  end

  it 'answers an action whose only render it pushed itself' do
    parent, child, channel = mount_tree

    send_batch(parent, child, :staged_only)

    expect(replies(channel.transmissions).size).to eq(1)
  end

  it 'answers a stream_from callback arriving during the batch on the same thread with one reply' do
    stream = live_mount('stream_test')
    stream.clear_broadcasts
    stream_component = stream.component
    def stream_component.noisy
      channel.broadcast_to('test_messages', { text: 'inner' })
    end
    stream_component.class.instance_variable_set(:@allowed_actions, nil)
    allow(stream_component.class).to receive(:allowed_actions).and_return([:noisy])

    stream.perform(:noisy)

    expect(replies(stream.broadcasts).size).to eq(1)
  end

  it 'answers a reactive write that changes nothing in the template with an ack' do
    parent, child, channel = mount_tree

    send_batch(parent, child, :invisible_change)

    expect(channel.transmissions).to eq([{ _ack: true }])
  end

  it 'sends the events of an action that raised after queueing them nowhere before the _error' do
    parent, child, channel = mount_tree(raise_errors: false)

    send_batch(parent, child, :announce_and_raise)

    expect(channel.transmissions.first).to have_key(:_error)
  end
end
