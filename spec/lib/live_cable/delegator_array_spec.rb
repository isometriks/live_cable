# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LiveCable::Delegator, 'Array delegation' do
  let(:container) { LiveCable::Container.new }
  let(:observer) { container.observer }
  let(:array) { %w[ruby rails rspec] }
  let(:delegator) do
    described_class.new(array).tap do |d|
      d.add_live_cable_observer(observer, :tags)
    end
  end

  describe 'getter methods' do
    it 'delegates [] without marking dirty' do
      result = delegator[0]

      expect(result).to eq('ruby')
      expect(container.changed?).to be false
    end

    it 'delegates map without marking dirty' do
      result = delegator.map(&:upcase)

      expect(result).to eq(%w[RUBY RAILS RSPEC])
      expect(container.changed?).to be false
    end

    it 'delegates select without marking dirty' do
      result = delegator.select { |item| item.start_with?('r') }

      expect(result).to eq(%w[ruby rails rspec])
      expect(container.changed?).to be false
    end

    it 'delegates reject without marking dirty' do
      result = delegator.reject { |item| item == 'rails' }

      expect(result).to eq(%w[ruby rspec])
      expect(container.changed?).to be false
    end

    it 'delegates compact without marking dirty' do
      delegator_with_nil = described_class.new(['ruby', nil, 'rails']).tap do |d|
        d.add_live_cable_observer(observer, :tags)
      end

      result = delegator_with_nil.compact

      expect(result).to eq(%w[ruby rails])
      expect(container.changed?).to be false
    end

    it 'delegates first without marking dirty' do
      result = delegator.first

      expect(result).to eq('ruby')
      expect(container.changed?).to be false
    end

    it 'delegates last without marking dirty' do
      result = delegator.last

      expect(result).to eq('rspec')
      expect(container.changed?).to be false
    end
  end

  describe 'mutative methods' do
    it 'marks container dirty when using <<' do
      delegator << 'minitest'

      expect(delegator.to_a).to eq(%w[ruby rails rspec minitest])
      expect(container.changeset).to include(:tags)
    end

    it 'marks container dirty when using push' do
      delegator.push('sidekiq')

      expect(delegator.to_a).to eq(%w[ruby rails rspec sidekiq])
      expect(container.changeset).to include(:tags)
    end

    it 'marks container dirty when using pop' do
      delegator.pop

      expect(delegator.to_a).to eq(%w[ruby rails])
      expect(container.changeset).to include(:tags)
    end

    it 'marks container dirty when using shift' do
      delegator.shift

      expect(delegator.to_a).to eq(%w[rails rspec])
      expect(container.changeset).to include(:tags)
    end

    it 'marks container dirty when using unshift' do
      delegator.unshift('crystal')

      expect(delegator.to_a).to eq(%w[crystal ruby rails rspec])
      expect(container.changeset).to include(:tags)
    end

    it 'marks container dirty when using delete' do
      delegator.delete('rails')

      expect(delegator.to_a).to eq(%w[ruby rspec])
      expect(container.changeset).to include(:tags)
    end

    it 'marks container dirty when using delete_at' do
      delegator.delete_at(1)

      expect(delegator.to_a).to eq(%w[ruby rspec])
      expect(container.changeset).to include(:tags)
    end

    it 'marks container dirty when using []=' do
      delegator[0] = 'elixir'

      expect(delegator.to_a).to eq(%w[elixir rails rspec])
      expect(container.changeset).to include(:tags)
    end

    it 'marks container dirty when using clear' do
      delegator.clear

      expect(delegator.to_a).to eq([])
      expect(container.changeset).to include(:tags)
    end

    it 'marks container dirty when using concat' do
      delegator.concat(%w[sinatra hanami]) # rubocop:disable Style/ConcatArrayLiterals

      expect(delegator.to_a).to eq(%w[ruby rails rspec sinatra hanami])
      expect(container.changeset).to include(:tags)
    end

    it 'marks container dirty when using sort!' do
      delegator.sort!

      expect(delegator.to_a).to eq(%w[rails rspec ruby])
      expect(container.changeset).to include(:tags)
    end

    it 'marks container dirty when using reverse!' do
      delegator.reverse!

      expect(delegator.to_a).to eq(%w[rspec rails ruby])
      expect(container.changeset).to include(:tags)
    end
  end

  describe '#each' do
    it 'iterates over wrapped elements' do
      results = []
      delegator.each { |item| results << item } # rubocop:disable Style/MapIntoArray

      expect(results).to eq(%w[ruby rails rspec])
    end

    it 'returns delegators for nested arrays' do
      nested_array = [%w[a b], %w[c d]]
      nested_delegator = described_class.new(nested_array).tap do |d|
        d.add_live_cable_observer(observer, :nested)
      end

      nested_delegator.each do |item|
        expect(item).to be_a(LiveCable::Delegator)
      end
    end
  end

  describe 'observer propagation' do
    it 'propagates observers to nested structures from getter methods' do
      nested = [['inner']]
      delegator = described_class.new(nested).tap do |d|
        d.add_live_cable_observer(observer, :nested)
      end

      inner_array = delegator[0]
      inner_array << 'new_item'

      expect(container.changeset).to include(:nested)
    end
  end

  describe '.supported?' do
    it 'returns true for arrays' do
      expect(described_class.supported?([])).to be true
    end

    it 'returns false for strings' do
      expect(described_class.supported?('string')).to be false
    end
  end
end
