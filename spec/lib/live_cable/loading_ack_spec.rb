# frozen_string_literal: true

require 'rails_helper'

# Every message batch must produce exactly one reply so the client can clear
# its loading state (live-loading / live-disable-with): the component's own
# _refresh, an _error, or an _ack when neither went out.
RSpec.describe 'Loading state acknowledgements' do
  include LiveCable::Testing

  it 'broadcasts an ack when an action changes nothing' do
    counter = live_mount('counter')
    counter.clear_broadcasts

    counter.perform(:noop)

    expect(counter.broadcasts(:_ack)).to eq([{ _ack: true }])
    expect(counter.broadcasts(:_refresh)).to be_empty
  end

  it 'broadcasts a refresh without an ack when an action changes state' do
    counter = live_mount('counter')
    counter.clear_broadcasts

    counter.perform(:increment)

    expect(counter.broadcasts(:_refresh).size).to eq(1)
    expect(counter.broadcasts(:_ack)).to be_empty
  end

  it 'broadcasts an ack when a reactive update sets the same value' do
    counter = live_mount('counter')
    counter.set_reactive(:step, '2')
    counter.clear_broadcasts

    counter.set_reactive(:step, '2')

    # Setting a variable always marks it dirty, so this re-renders; the
    # invariant under test is that exactly one response is sent either way
    expect(counter.broadcasts(:_refresh).size + counter.broadcasts(:_ack).size).to eq(1)
  end

  it 'sends the error as the response when an action raises' do
    counter = live_mount('counter', raise_errors: false)
    counter.clear_broadcasts

    counter.perform(:missing_action)

    expect(counter.broadcasts(:_error).size).to eq(1)
    # The _error is the batch's one response - no trailing _ack
    expect(counter.broadcasts(:_ack)).to be_empty
  end

  describe 'replies' do
    it 'marks the acting component\'s render as the reply' do
      counter = live_mount('counter')
      counter.clear_broadcasts

      counter.perform(:increment)

      expect(counter.broadcasts(:_refresh).map { |frame| frame[:_reply] }).to eq([true])
    end

    it 'marks a render the action pushes before it finishes as no reply' do
      loading = live_mount('loading')
      loading.clear_broadcasts

      loading.perform(:staged_increment)

      expect(loading.broadcasts(:_refresh).map { |frame| frame[:_reply] }).to eq([false, true])
      expect(loading.rendered).to have_css('[data-testid="count"]', exact_text: '2')
    end

    it 'marks a render pushed by a stream_from callback as no reply' do
      stream = live_mount('stream_test')
      stream.clear_broadcasts

      stream.receive_stream('test_messages', { text: 'hello' })

      expect(stream.broadcasts(:_refresh).map { |frame| frame[:_reply] }).to eq([false])
    end

    it 'marks the render of a component sharing state with the actor as no reply' do
      first = live_mount('shared_counter', id: 'first')
      second = live_mount('shared_counter', id: 'second', connection: first.connection)
      first.clear_broadcasts
      second.clear_broadcasts

      first.perform(:bump)

      expect(first.broadcasts(:_refresh).map { |frame| frame[:_reply] }).to eq([true])
      expect(second.broadcasts(:_refresh).map { |frame| frame[:_reply] }).to eq([false])
      expect(second.broadcasts(:_ack)).to be_empty
    end

    it 'acks an acting child whose render rode in its parent\'s refresh' do
      list = live_mount('todo_list')
      todo = list.connection.get_component('todo/write')
      todo_channel = LiveCable::Testing::TestChannel.new
      todo.connect(todo_channel)
      list.clear_broadcasts

      list.connection.receive(todo, { 'messages' => [{ '_action' => 'complete' }] })

      expect(list.broadcasts(:_refresh).sole).to include(_reply: false)
      expect(list.broadcasts(:_refresh).sole[:_refresh][:c]).to have_key('todo/write')
      expect(todo_channel.transmissions).to eq([{ _ack: true, _rendered: true }])
    end

    it 'acks an acting child that its parent rendered with nothing new as not rendered' do
      list = live_mount('todo_list')
      todo = list.connection.get_component('todo/write')
      todo_channel = LiveCable::Testing::TestChannel.new
      todo.connect(todo_channel)
      list.clear_broadcasts

      list.connection.receive(todo, { 'messages' => [{ '_action' => 'star' }] })

      expect(list.rendered).to have_css('li', text: '★')
      expect(list.broadcasts(:_refresh).sole[:_refresh]).not_to have_key(:c)
      expect(todo_channel.transmissions).to eq([{ _ack: true }])
    end

    it 'marks the render sent on subscribe' do
      counter = live_mount('counter')

      expect(counter.broadcasts(:_refresh).sole).to include(_subscribed: true, _reply: false)
    end
  end
end
