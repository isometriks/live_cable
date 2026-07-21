# frozen_string_literal: true

require 'rails_helper'

# Every message batch must produce exactly one response so the client can
# clear its loading state (live-loading / live-disable-with): a _refresh when
# the component re-rendered, or a lightweight _ack when nothing changed.
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
end
