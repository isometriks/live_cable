# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Children rendered inline by a parent' do
  include LiveCable::Testing

  # A child its parent rendered inline gets broadcast_subscribe, not a render,
  # when its own subscription arrives - as LiveChannel#subscribed does
  def subscribe(parent, live_id)
    child = parent.connection.get_component(live_id)
    channel = LiveCable::Testing::TestChannel.new
    child.connect(channel)
    child.broadcast_subscribe

    LiveCable::Testing::TestComponent.new(child, parent.connection, channel)
  end

  it 'destroys a child hidden after a render that skipped its part' do
    holder = live_mount('holder')
    counter = subscribe(holder, 'shared_counter/test-counter')

    holder.perform(:bump)
    expect(counter.broadcasts(:_status)).not_to include({ _status: 'destroy' })

    holder.perform(:hide)
    expect(counter.broadcasts(:_status)).to include({ _status: 'destroy' })
  end

  it 'destroys a child hidden after its parent was rendered inline with nothing changed' do
    list = live_mount('holder_list')
    holder = subscribe(list, 'holder/holder-0')
    counter = subscribe(list, 'shared_counter/holder-0-counter')

    list.perform(:add)
    expect(counter.broadcasts(:_status)).not_to include({ _status: 'destroy' })

    holder.perform(:hide)
    expect(counter.broadcasts(:_status)).to include({ _status: 'destroy' })
  end

  it 'destroys the children of a removed child after a render that skipped their part' do
    list = live_mount('holder_list')
    holder = subscribe(list, 'holder/holder-0')
    counter = subscribe(list, 'shared_counter/holder-0-counter')

    holder.perform(:bump)
    list.perform(:remove)

    expect(holder.broadcasts(:_status)).to include({ _status: 'destroy' })
    expect(counter.broadcasts(:_status)).to include({ _status: 'destroy' })
  end

  it 'destroys its children when a render after a skip fails' do
    holder = live_mount('holder', raise_errors: false)
    counter = subscribe(holder, 'shared_counter/test-counter')

    holder.perform(:bump)
    holder.perform(:break_render)

    expect(counter.broadcasts(:_status)).to include({ _status: 'destroy' })
    expect(holder.broadcasts(:_error)).not_to be_empty
  end

  it 'destroys a child that only its previous variant rendered' do
    holder = live_mount('compound_holder')
    counter = subscribe(holder, 'shared_counter/compound-counter')

    holder.perform(:hide)

    expect(counter.broadcasts(:_status)).to include({ _status: 'destroy' })
  end

  it 'still renders a child on its own channel when its parent skipped its part in the same cycle' do
    holder = live_mount('holder')
    counter = subscribe(holder, 'shared_counter/test-counter')
    counter.clear_broadcasts

    holder.perform(:bump_total)

    expect(counter.broadcasts(:_refresh).size).to eq(1)
  end
end
