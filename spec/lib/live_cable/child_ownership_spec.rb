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

  it 'builds a hidden child again when it is shown before its unsubscribe arrives' do
    host = live_mount('toggle_host')
    counter = subscribe(host, 'counter/toggled')
    counter.perform(:increment)

    host.perform(:flip)
    expect(counter.broadcasts(:_status)).to include({ _status: 'destroy' })
    expect(host.connection.get_component('counter/toggled')).to be_nil

    host.clear_broadcasts
    host.perform(:flip)

    shown = host.connection.get_component('counter/toggled')
    expect(shown).not_to equal(counter.component)
    expect(shown.count).to eq(0)
    expect(host.broadcasts(:_refresh).last.dig(:_refresh, :c, 'counter/toggled', :p)).to all(be_a(String))
  end

  it 'takes a hidden child that never subscribed off the connection without disconnecting it' do
    holder = live_mount('holder')
    counter = holder.connection.get_component('shared_counter/test-counter')
    allow(counter).to receive(:disconnect)

    holder.perform(:hide)

    expect(holder.connection.get_component('shared_counter/test-counter')).to be_nil
    expect(counter).not_to have_received(:disconnect)
  end

  it 'reports a hidden child whose disconnect callback raises, and still renders its parent' do
    holder = live_mount('holder')
    counter = subscribe(holder, 'shared_counter/test-counter')
    allow(counter.component).to receive(:run_callbacks).and_wrap_original do |original, kind, &block|
      kind == :disconnect ? raise('boom') : original.call(kind, &block)
    end
    allow(Rails.error).to receive(:report)
    holder.clear_broadcasts

    holder.perform(:hide)

    expect(Rails.error).to have_received(:report).with(an_object_having_attributes(message: 'boom'))
    expect(holder.broadcasts(:_refresh).size).to eq(1)
    expect(holder.connection.get_component('shared_counter/test-counter')).to be_nil
  end

  [%w[card-1 todo doing], %w[card-3 doing todo]].each do |card_id, from, to|
    it "keeps a child that moves from #{from} to #{to} in the same render cycle" do
      lanes = live_mount('lanes')
      subscribe(lanes, 'lane/lane-todo')
      target = subscribe(lanes, "lane/lane-#{to}")
      card = subscribe(lanes, "lane_card/#{card_id}")
      card.perform(:note)
      target.clear_broadcasts

      card.perform(:advance)

      expect(card.broadcasts(:_status)).not_to include({ _status: 'destroy' })
      expect(lanes.connection.get_component("lane_card/#{card_id}")).to equal(card.component)
      expect(target.broadcasts(:_refresh).last[:_refresh][:p].join).to include("child-live-id=\"lane_card/#{card_id}\"")
      expect(card.notes).to eq(1)
    end
  end

  it 'still renders a child on its own channel when its parent skipped its part in the same cycle' do
    holder = live_mount('holder')
    counter = subscribe(holder, 'shared_counter/test-counter')
    counter.clear_broadcasts

    holder.perform(:bump_total)

    expect(counter.broadcasts(:_refresh).size).to eq(1)
  end
end
