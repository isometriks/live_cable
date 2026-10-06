# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'before_dispatch' do
  include LiveCable::Testing

  it 'runs before an action, with its name and params' do
    guarded = live_mount('guarded')

    guarded.perform(:increment, by: 2)

    expect(guarded.dispatches.map { |d| [d.kind, d.name, d.params[:by]] }).to eq([[:action, :increment, '2']])
    expect(guarded.count).to eq(2)
  end

  it 'runs before a reactive write, with its name and value' do
    guarded = live_mount('guarded')

    guarded.set_reactive(:name, 'alice')

    expect(guarded.dispatches.map { |d| [d.kind, d.name, d.value] }).to eq([[:reactive, :name, 'alice']])
    expect(guarded.name).to eq('alice')
  end

  it 'leaves current_dispatch unset outside a dispatch' do
    guarded = live_mount('guarded')

    guarded.perform(:increment)

    expect(guarded.current_dispatch).to be_nil
  end

  it 'skips an action it halts and still answers the message' do
    guarded = live_mount('guarded', mode: 'abort')
    guarded.clear_broadcasts

    guarded.perform(:increment)

    expect(guarded.count).to eq(0)
    expect(guarded.broadcasts).to eq([{ _ack: true }])
  end

  it 'skips a reactive write it halts' do
    guarded = live_mount('guarded', mode: 'abort')

    guarded.set_reactive(:name, 'mallory')

    expect(guarded.name).to eq('')
  end

  it 'offers an error it raises to rescue_from and renders what the handler set' do
    guarded = live_mount('guarded', mode: 'raise')

    guarded.set_reactive(:name, 'mallory')

    expect(guarded.name).to eq('')
    expect(guarded.rendered).to have_css('[data-testid="notice"]', text: 'refused')
    expect(guarded.broadcasts(:_error)).to be_empty
  end

  it 'still refuses a message the component does not expose, without running' do
    guarded = live_mount('guarded', raise_errors: false)

    guarded.perform(:authorize!)

    expect(guarded.broadcasts(:_error)).not_to be_empty
    expect(guarded.dispatches).to be_empty
  end

  it 'does not run for defaults applied at mount or for server-side writes' do
    guarded = live_mount('guarded', name: 'from defaults')

    guarded.perform(:rename)

    expect(guarded.dispatches.map(&:name)).to eq([:rename])
    expect(guarded.name).to eq('server')
  end

  it 'does not run for stream_from callbacks' do
    guarded = live_mount('guarded')
    guarded.perform(:subscribe_to_feed)

    guarded.receive_stream('guarded', { 'count' => 5 })

    expect(guarded.dispatches.map(&:name)).to eq([:subscribe_to_feed])
    expect(guarded.count).to eq(5)
  end
end
