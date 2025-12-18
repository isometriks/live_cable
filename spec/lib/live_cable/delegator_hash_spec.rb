# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LiveCable::Delegator, 'Hash delegation' do
  let(:container) { LiveCable::Container.new }
  let(:observer) { container.observer }
  let(:hash) { { name: 'John', age: 30, city: 'NYC' } }
  let(:delegator) do
    described_class.new(hash).tap do |d|
      d.add_live_cable_observer(observer, :user)
    end
  end

  describe 'getter methods' do
    it 'delegates [] without marking dirty' do
      result = delegator[:name]

      expect(result).to eq('John')
      expect(container.changed?).to be false
    end

    it 'returns wrapped nested hashes from []' do
      nested_hash = { profile: { bio: 'Developer' } }
      delegator = described_class.new(nested_hash).tap do |d|
        d.add_live_cable_observer(observer, :user)
      end

      result = delegator[:profile]

      expect(result).to be_a(LiveCable::Delegator)
      expect(result[:bio]).to eq('Developer')
    end
  end

  describe 'mutative methods' do
    it 'marks container dirty when using []=' do
      delegator[:email] = 'john@example.com'

      expect(delegator[:email]).to eq('john@example.com')
      expect(container.changeset).to include(:user)
    end

    it 'marks container dirty when updating existing key' do
      delegator[:name] = 'Jane'

      expect(delegator[:name]).to eq('Jane')
      expect(container.changeset).to include(:user)
    end

    it 'marks container dirty when using delete' do
      delegator.delete(:city)

      expect(delegator[:city]).to be_nil
      expect(container.changeset).to include(:user)
    end

    it 'marks container dirty when using clear' do
      delegator.clear

      expect(delegator.to_h).to eq({})
      expect(container.changeset).to include(:user)
    end

    it 'marks container dirty when using merge!' do
      delegator.merge!(country: 'USA', state: 'NY')

      expect(delegator[:country]).to eq('USA')
      expect(delegator[:state]).to eq('NY')
      expect(container.changeset).to include(:user)
    end

    it 'marks container dirty when using update' do
      delegator.update(age: 31)

      expect(delegator[:age]).to eq(31)
      expect(container.changeset).to include(:user)
    end

    it 'marks container dirty when using delete_if' do
      delegator.delete_if { |_k, v| v.is_a?(Integer) }

      expect(delegator[:age]).to be_nil
      expect(delegator[:name]).to eq('John')
      expect(container.changeset).to include(:user)
    end

    it 'marks container dirty when using keep_if' do
      delegator.keep_if { |_k, v| v.is_a?(String) }

      expect(delegator[:age]).to be_nil
      expect(delegator[:name]).to eq('John')
      expect(container.changeset).to include(:user)
    end

    it 'marks container dirty when using select!' do
      delegator.select! { |_k, v| v.is_a?(String) }

      expect(delegator[:age]).to be_nil
      expect(delegator[:name]).to eq('John')
      expect(container.changeset).to include(:user)
    end

    it 'marks container dirty when using reject!' do
      delegator.reject! { |_k, v| v.is_a?(Integer) }

      expect(delegator[:age]).to be_nil
      expect(delegator[:name]).to eq('John')
      expect(container.changeset).to include(:user)
    end

    it 'marks container dirty when using compact!' do
      hash_with_nil = { a: 1, b: nil, c: 3 }
      delegator = described_class.new(hash_with_nil).tap do |d|
        d.add_live_cable_observer(observer, :data)
      end

      delegator.compact!

      expect(delegator.to_h).to eq({ a: 1, c: 3 })
      expect(container.changeset).to include(:data)
    end

    it 'marks container dirty when using transform_values!' do
      delegator.transform_values! { |v| v.is_a?(String) ? v.upcase : v }

      expect(delegator[:name]).to eq('JOHN')
      expect(delegator[:city]).to eq('NYC')
      expect(container.changeset).to include(:user)
    end

    it 'marks container dirty when using transform_keys!' do
      delegator.transform_keys! { |k| :"new_#{k}" }

      expect(delegator[:new_name]).to eq('John')
      expect(delegator[:name]).to be_nil
      expect(container.changeset).to include(:user)
    end
  end

  describe 'observer propagation to nested hashes' do
    it 'propagates observers to nested hashes accessed via []' do
      nested = { profile: { bio: 'Developer' } }
      delegator = described_class.new(nested).tap do |d|
        d.add_live_cable_observer(observer, :user)
      end

      profile = delegator[:profile]
      profile[:bio] = 'Senior Developer'

      expect(container.changeset).to include(:user)
    end

    it 'propagates observers through multiple levels of nesting' do
      deeply_nested = { level1: { level2: { level3: 'value' } } }
      delegator = described_class.new(deeply_nested).tap do |d|
        d.add_live_cable_observer(observer, :data)
      end

      level3 = delegator[:level1][:level2]
      level3[:level3] = 'new_value'

      expect(container.changeset).to include(:data)
    end
  end

  describe 'Rails-specific hash methods' do
    it 'marks container dirty when using stringify_keys!' do
      delegator.stringify_keys!

      expect(delegator['name']).to eq('John')
      expect(container.changeset).to include(:user)
    end

    it 'marks container dirty when using symbolize_keys!' do
      string_hash = { 'name' => 'John', 'age' => 30 }
      delegator = described_class.new(string_hash).tap do |d|
        d.add_live_cable_observer(observer, :user)
      end

      delegator.symbolize_keys!

      expect(delegator[:name]).to eq('John')
      expect(container.changeset).to include(:user)
    end

    it 'marks container dirty when using deep_merge!' do
      delegator[:nested] = { a: 1 }
      container.reset_changeset

      delegator.deep_merge!(nested: { b: 2 })

      expect(delegator[:nested]).to be_a(LiveCable::Delegator)
      expect(container.changeset).to include(:user)
    end
  end

  describe '.supported?' do
    it 'returns true for hashes' do
      expect(described_class.supported?({})).to be true
    end

    it 'returns false for strings' do
      expect(described_class.supported?('string')).to be false
    end
  end
end
