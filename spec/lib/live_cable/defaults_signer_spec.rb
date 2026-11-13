# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LiveCable::DefaultsSigner do
  let(:live_id) { 'counter/c1' }

  it 'round-trips signed defaults bound to a live_id' do
    blob = described_class.sign({ count: 5, step: 2 }, live_id)

    expect(described_class.verify(blob, live_id)).to eq('count' => 5, 'step' => 2)
  end

  # The client compares blobs to tell whether a component's defaults changed
  it 'signs the same defaults to the same blob whatever order they were given in' do
    expect(described_class.sign({ count: 5, step: 2 }, live_id)).
      to eq(described_class.sign({ 'step' => 2, count: 5 }, live_id))
  end

  it 'signs equal nested hashes to the same blob whatever order their keys were given in' do
    one = { filters: { a: 1, b: { y: 2, z: 3 } }, rows: [{ id: 1, name: 'x' }] }
    two = { filters: { b: { z: 3, y: 2 }, a: 1 }, rows: [{ name: 'x', id: 1 }] }

    expect(described_class.sign(one, live_id)).to eq(described_class.sign(two, live_id))
  end

  it 'returns an empty hash for a blank blob' do
    expect(described_class.verify(nil, live_id)).to eq({})
    expect(described_class.verify('', live_id)).to eq({})
  end

  it 'returns an empty hash for a blob that is not a string' do
    expect(described_class.verify({ 'count' => 5 }, live_id)).to eq({})
    expect(described_class.verify([1], live_id)).to eq({})
    expect(described_class.verify(5, live_id)).to eq({})
  end

  it 'rejects a tampered blob' do
    blob = described_class.sign({ count: 5 }, live_id)
    tampered = "#{blob}x"

    expect(described_class.verify(tampered, live_id)).to eq({})
  end

  it 'rejects a blob bound to a different live_id (no replay onto another component)' do
    blob = described_class.sign({ count: 5 }, live_id)

    expect(described_class.verify(blob, 'counter/other')).to eq({})
  end

  it 'signs the JSON form of each default' do
    blob = described_class.sign({ at: Time.utc(2026, 1, 1), kind: :open }, live_id)

    expect(described_class.verify(blob, live_id)).to eq('at' => '2026-01-01T00:00:00.000Z', 'kind' => 'open')
  end

  describe '.round_trip' do
    before { allow(LiveCable).to receive(:warn_once) }

    it 'returns the defaults as the client will send them back' do
      round_tripped = described_class.round_trip({ kind: :open, filters: { page: 1 } }, Live::Counter)

      expect(round_tripped).to eq('kind' => 'open', 'filters' => { 'page' => 1 })
    end

    it 'orders nested keys as the verified blob does' do
      defaults = { filters: { b: 2, a: { z: 1, y: 2 } }, rows: [{ name: 'x', id: 1 }] }
      verified = described_class.verify(described_class.sign(defaults, live_id), live_id)

      round_tripped = described_class.round_trip(defaults, Live::Counter)

      expect(round_tripped['filters'].keys).to eq(%w[a b])
      expect(round_tripped['filters']['a'].keys).to eq(%w[y z])
      expect(round_tripped['rows'].first.keys).to eq(%w[id name])
      expect(round_tripped.inspect).to eq(verified.inspect)
    end

    it 'warns about a default that is not JSON-native' do
      described_class.round_trip({ count: 1, kind: :open }, Live::Counter)

      expect(LiveCable).to have_received(:warn_once).once
      expect(LiveCable).to have_received(:warn_once).with(/Live::Counter default :kind \(Symbol\)/)
    end

    it 'stays quiet about JSON-native defaults' do
      described_class.round_trip({ 'count' => 1, step: 2.5, tags: ['a'], meta: { 'a' => nil } }, Live::Counter)

      expect(LiveCable).not_to have_received(:warn_once)
    end

    it 'refuses any other default that is not JSON-native, naming what it holds' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('production'))

      pair = Struct.new(:a)

      [[Object.new, Object], [pair.new(1), pair], [Set[1], Set], [[1, 1..2], Range]].each do |value, held|
        message = "Live::Counter default :value (#{value.class}) is or holds an object (#{held}) that isn't JSON-native"

        expect { described_class.round_trip({ count: 1, value: }, Live::Counter) }.
          to raise_error(ArgumentError, /\A#{Regexp.escape(message)}/)
      end
    end

    it 'accepts times, dates and other numbers, which round-trip as their JSON form' do
      at = Time.utc(2026, 1, 1)
      defaults = { at:, zone: at.in_time_zone, on: Date.new(2026, 1, 2), price: BigDecimal('1.5'), wait: 5.minutes }

      expect(described_class.round_trip(defaults, Live::Counter)).to eq(
        'at' => '2026-01-01T00:00:00.000Z', 'zone' => '2026-01-01T00:00:00.000Z', 'on' => '2026-01-02',
        'price' => '1.5', 'wait' => 300
      )
    end

    context 'with a record' do
      include LiveCable::Testing

      let(:user) { User.create!(name: 'Ann') }

      before do
        ActiveRecord::Schema.define do
          suppress_messages do
            create_table :signer_users, force: true do |t|
              t.string :name
            end
          end
        end

        stub_const('User', Class.new(ActiveRecord::Base) { self.table_name = 'signer_users' })
      end

      it 'refuses it in every environment, naming the component, the key and the class' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('production'))

        expect { described_class.round_trip({ count: 1, user: }, Live::Counter) }.
          to raise_error(ArgumentError, /\ALive::Counter default :user \(User\) .* Pass its id/)
      end

      it 'refuses one inside an Array or Hash, and a relation' do
        [[user], { 'owner' => user }, { team: [1, user] }, User.all].each do |value|
          expect { described_class.round_trip({ value: }, Live::Counter) }.
            to raise_error(ArgumentError, /default :value \(#{Regexp.escape(value.class.to_s)}\)/)
        end
      end

      it 'refuses one inside a Struct, a Set or a plain object, in every environment' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('production'))
        presenter = Class.new { def initialize(user) = @user = user }

        [Struct.new(:user).new(user), Set[user], presenter.new(user), { cards: [Set[user]] }].each do |value|
          expect { described_class.round_trip({ value: }, Live::Counter) }.
            to raise_error(ArgumentError, /default :value \(#{Regexp.escape(value.class.to_s)}\) .* Pass/)
        end
      end

      it 'refuses one behind a delegator, as component code reads a reactive variable' do
        tracked = ->(kind) { live_mount('default_kind', kind:).component.kind }

        [
          [tracked.call(user), 'User'],
          [tracked.call([user]), 'Array'],
          [tracked.call({ 'owner' => user }), 'Hash'],
          [[tracked.call(user)], 'Array'],
          [SimpleDelegator.new(user), 'User'],
        ].each do |value, class_name|
          expect { described_class.round_trip({ value: }, Live::Counter) }.
            to raise_error(ArgumentError, /default :value \(#{class_name}\)/)
        end
      end

      it 'fails the page load of a top-level component' do
        template = "<%= live('default_kind', id: 'k1', kind: user) %>"

        expect { ApplicationController.render(inline: template, locals: { user: }) }.
          to raise_error(ActionView::Template::Error, /default :kind \(User\)/)
      end

      it 'fails the page load of a top-level component given an object holding one, in production too' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('production'))
        template = "<%= live('default_kind', id: 'k1', kind: card) %>"
        card = Struct.new(:user, :title).new(user, 'Profile')

        expect { ApplicationController.render(inline: template, locals: { card: }) }.
          to raise_error(ActionView::Template::Error, /default :kind \(.*\) is or holds an object/)
      end

      it 'leaves a record passed to live_mount as it is' do
        expect(live_mount('default_kind', kind: user).kind.name).to eq('Ann')
      end
    end
  end

  describe 'the writable bypass it prevents' do
    # Live::Counter marks only :step writable; :count is server-only.
    it 'ignores tampered defaults, leaving non-writable variables untouched' do
      component = Live::Counter.new('c1')

      # A value the client fabricated (not signed by the server)
      component.defaults = described_class.verify('not-a-valid-blob', component.live_id)
      component.apply_defaults

      expect(component.count).to eq(0)
    end

    it 'still applies legitimately signed server defaults' do
      component = Live::Counter.new('c1')
      blob = described_class.sign({ count: 99 }, component.live_id)

      component.defaults = described_class.verify(blob, component.live_id)
      component.apply_defaults

      expect(component.count).to eq(99)
    end
  end
end
