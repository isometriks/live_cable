# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Component#refuse!' do
  include LiveCable::Testing

  def mount(**defaults)
    live_mount('revocable', **defaults).tap(&:clear_broadcasts)
  end

  it 'refuses the component with the reason, and an error box for clients that show one' do
    revocable = mount

    revocable.perform(:leave)

    expect(revocable.broadcasts).to match([
      a_hash_including(_refused: true, _reason: 'membership_ended', _error: a_string_including('<details>')),
    ])
  end

  it 'answers the message batch with the refusal alone' do
    revocable = mount

    revocable.perform(:leave)

    expect(revocable.broadcasts.map(&:keys)).to eq([%i[_error _refused _reason]])
  end

  it 'is not offered to rescue_from' do
    revocable = mount

    revocable.perform(:leave)

    expect(revocable.notice).to eq('')
  end

  it 'is not reported as an error' do
    allow(Rails.error).to receive(:report)
    revocable = mount

    revocable.perform(:leave)

    expect(Rails.error).not_to have_received(:report)
  end

  it 'stops the action when a before_dispatch refuses' do
    revocable = mount(access: 'revoked')

    revocable.perform(:increment)

    expect(revocable.count).to eq(0)
    expect(revocable.broadcasts(:_refused)).to match([a_hash_including(_reason: 'no_access')])
  end

  it 'refuses from a stream callback' do
    revocable = mount

    revocable.receive_stream('revocable', { 'reason' => 'account_deleted' })

    expect(revocable.broadcasts(:_refused)).to match([a_hash_including(_reason: 'account_deleted')])
  end

  it 'sends a nil reason when given none' do
    revocable = mount

    revocable.receive_stream('revocable', {})

    expect(revocable.broadcasts(:_refused)).to match([a_hash_including(_reason: nil)])
  end

  it 'refuses on subscribe instead of rendering' do
    revocable = live_mount('revocable', access: 'none_on_connect')

    expect(revocable.broadcasts.map(&:keys)).to eq([%i[_error _refused _reason]])
    expect(revocable).to be_refused
  end

  it 'says whether the component was refused' do
    revocable = mount
    expect(revocable).not_to be_refused

    revocable.perform(:leave)

    expect(revocable).to be_refused
  end

  it 'stops the component on the server, so a message sent afterwards does nothing' do
    revocable = mount
    allow(revocable.component).to receive(:increment)
    revocable.perform(:leave)
    revocable.clear_broadcasts

    revocable.perform(:increment)

    expect(revocable.component).not_to have_received(:increment)
    expect(revocable.broadcasts).to be_empty
  end

  it 'skips the rest of the message batch' do
    revocable = mount
    allow(revocable.component).to receive(:increment)

    revocable.connection.receive(revocable.component, {
      'messages' => [{ '_action' => 'leave' }, { '_action' => 'increment' }],
    })

    expect(revocable.component).not_to have_received(:increment)
    expect(revocable.broadcasts.map(&:keys)).to eq([%i[_error _refused _reason]])
  end

  it 'disconnects the component, stopping its streams' do
    revocable = mount
    allow(revocable.component).to receive(:disconnect).and_call_original

    revocable.perform(:leave)

    expect(revocable.component).to have_received(:disconnect).once
    expect(revocable.channel.streams).to be_empty
    expect(revocable.connection.get_component(revocable.live_id)).to be_nil
  end

  it 'takes the children it renders off the connection with it' do
    panel = live_mount('panel')

    panel.connection.handle_error(panel.component, LiveCable::Refused.new('gone'))

    expect(panel.connection.get_component('counter/panel-0')).to be_nil
  end

  it 'drops a stream broadcast that arrives after the refusal' do
    revocable = mount
    callback = revocable.channel.streams.fetch('revocable')[:callback]
    revocable.perform(:leave)
    revocable.clear_broadcasts

    callback.call('reason' => 'account_deleted')

    expect(revocable.broadcasts).to be_empty
  end

  [true, false].each do |raise_errors|
    it "refuses from a rescue_from handler with raise_errors: #{raise_errors}" do
      revocable = live_mount('revocable', raise_errors:).tap(&:clear_broadcasts)

      expect { revocable.perform(:vanish) }.not_to raise_error

      expect(revocable.broadcasts.map(&:keys)).to eq([%i[_error _refused _reason]])
      expect(revocable.broadcasts.last[:_reason]).to eq('gone')
    end
  end

  describe 'an inline child' do
    def mount_list
      list = live_mount('guest_list')
      guests = %w[a b].to_h do |id|
        [id, live_mount(list.connection.get_component("guest/#{id}"), connection: list.connection)]
      end
      [list, *guests.values].each(&:clear_broadcasts)
      [list, guests]
    end

    def sent_children(list)
      list.broadcasts(:_refresh).each_with_object({}) { |frame, sent| sent.merge!(frame[:_refresh][:c] || {}) }
    end

    it 'refuses itself, not its parent, when it refuses while the parent renders it' do
      list, guests = mount_list

      list.perform(:revoke, id: 'a')

      expect(guests['a'].broadcasts(:_refused)).to match([a_hash_including(_reason: 'revoked')])
      expect(list).not_to be_refused
      expect(sent_children(list)).not_to have_key('guest/a')
      expect(list.connection.get_component(list.live_id)).to equal(list.component)
      expect(list.connection.get_component('guest/b')).to equal(guests['b'].component)
      expect(list.connection.get_component('guest/a')).to be_nil
    end

    it 'is not built again by its parent' do
      list, guests = mount_list
      guests['a'].perform(:ping)
      guests['a'].perform(:leave)

      list.perform(:tick)

      expect(sent_children(list)).not_to have_key('guest/a')
      expect(list.connection.get_component('guest/a')).to be_nil
    end

    it 'is built again once its parent has stopped rendering it' do
      list, guests = mount_list
      guests['a'].perform(:ping)
      guests['a'].perform(:leave)
      list.perform(:drop, id: 'a')

      list.perform(:restore, id: 'a')

      expect(sent_children(list)).to have_key('guest/a')
      expect(list.connection.get_component('guest/a').pings).to eq(0)
    end

    it 'is built again by a parent that replaces the one that kept it' do
      list, guests = mount_list
      guests['a'].perform(:leave)
      list.unmount

      again = live_mount('guest_list', connection: list.connection)

      expect(again.connection.get_component('guest/a')).to be_a(Live::Guest)
    end

    it 'goes with its parent when the parent refuses after rendering it' do
      list, guests = mount_list

      list.perform(:close)

      expect(list.broadcasts(:_refused)).to match([a_hash_including(_reason: 'list_gone')])
      expect(guests['a'].broadcasts.map(&:keys)).to eq([%i[_status]])
      expect(guests['a'].component).not_to be_connected
      expect(list.connection.get_component('guest/a')).to be_nil
      expect(list.connection.get_component('guest/b')).to be_nil
    end
  end

  it 'leaves raise_errors to raise everything else' do
    revocable = mount
    allow(revocable.component).to receive(:increment).and_raise(ArgumentError)
    allow(revocable.component).to receive(:rescue_with_handler).and_return(false)

    expect { revocable.perform(:increment) }.to raise_error(ArgumentError)
  end
end
