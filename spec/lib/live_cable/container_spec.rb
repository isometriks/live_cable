# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LiveCable::Container do
  let(:container) { described_class.new }

  describe '#[]=' do
    it 'stores values in the container' do
      container[:username] = 'john_doe'

      expect(container[:username]).to eq('john_doe')
    end

    context 'with arrays' do
      it 'wraps array values in a Delegator' do
        container[:tags] = %w[ruby rails]

        expect(container[:tags]).to be_a(LiveCable::Delegator)
        expect(container[:tags].to_a).to eq(%w[ruby rails])
      end

      it 'adds observer to wrapped arrays' do
        container[:tags] = %w[ruby rails]
        container[:tags] << 'rspec'

        expect(container.changeset).to include(:tags)
      end
    end

    context 'with hashes' do
      it 'wraps hash values in a Delegator' do
        container[:settings] = { theme: 'dark' }

        expect(container[:settings]).to be_a(LiveCable::Delegator)
        expect(container[:settings][:theme]).to eq('dark')
      end

      it 'adds observer to wrapped hashes' do
        container[:settings] = { theme: 'dark' }
        container[:settings][:language] = 'en'

        expect(container.changeset).to include(:settings)
      end
    end

    context 'with unsupported types' do
      it 'stores strings without wrapping' do
        container[:name] = 'John'

        expect(container[:name]).to eq('John')
        expect(container[:name]).not_to be_a(LiveCable::Delegator)
      end

      it 'stores numbers without wrapping' do
        container[:count] = 42

        expect(container[:count]).to eq(42)
        expect(container[:count]).not_to be_a(LiveCable::Delegator)
      end
    end

    context 'with existing Delegator' do
      it 'does not double-wrap delegators' do
        delegator = LiveCable::Delegator.new(['ruby'])
        container[:tags] = delegator

        expect(container[:tags]).to be(delegator)
      end
    end
  end

  describe '#mark_dirty' do
    it 'adds variable to the changeset' do
      container.mark_dirty(:username)

      expect(container.changeset).to include(:username)
    end

    it 'adds multiple variables to the changeset' do
      container.mark_dirty(:username, :email, :age)

      expect(container.changeset).to contain_exactly(:username, :email, :age)
    end

    it 'keeps changeset unique when marking same variable multiple times' do
      container.mark_dirty(:username)
      container.mark_dirty(:username)

      expect(container.changeset).to eq([:username])
    end
  end

  describe '#changed?' do
    it 'returns false when changeset is empty' do
      expect(container.changed?).to be false
    end

    it 'returns true when changeset has items' do
      container.mark_dirty(:username)

      expect(container.changed?).to be true
    end
  end

  describe '#reset_changeset' do
    it 'clears the changeset' do
      container.mark_dirty(:username, :email)
      container.reset_changeset

      expect(container.changeset).to be_empty
      expect(container.changed?).to be false
    end

    it 'does not affect stored values' do
      container[:username] = 'john_doe'
      container.reset_changeset

      expect(container[:username]).to eq('john_doe')
    end
  end

  describe '#observer' do
    it 'returns an Observer instance' do
      expect(container.observer).to be_a(LiveCable::Observer)
    end

    it 'returns the same observer instance on multiple calls' do
      observer1 = container.observer
      observer2 = container.observer

      expect(observer1).to be(observer2)
    end
  end

  describe '#cleanup' do
    it 'removes only this containers observer from delegated values' do
      container[:tags] = %w[ruby rails]
      delegator = container[:tags]
      observer = container.observer

      # Verify observer is attached
      observers = delegator.instance_variable_get(:@live_cable_observers)
      expect(observers[:tags]).to include(observer)

      container.cleanup

      # Verify this specific observer reference is removed
      observers = delegator.instance_variable_get(:@live_cable_observers)
      expect(observers[:tags]).not_to include(observer)
    end

    it 'does not remove observers from other containers' do
      # Create two containers sharing the same array
      shared_array = %w[ruby rails]

      container[:tags] = shared_array
      container2 = described_class.new
      container2[:tags] = container[:tags] # Share the delegator

      observer1 = container.observer
      observer2 = container2.observer

      # Both observers should be attached
      delegator = container[:tags]
      observers = delegator.instance_variable_get(:@live_cable_observers)
      expect(observers[:tags]).to include(observer1, observer2)

      # Clean up first container
      container.cleanup

      # Only observer1 should be removed, observer2 should remain
      observers = delegator.instance_variable_get(:@live_cable_observers)
      expect(observers[:tags]).not_to include(observer1)
      expect(observers[:tags]).to include(observer2)
    end

    it 'clears the container data' do
      container[:username] = 'john_doe'
      container[:tags] = %w[ruby rails]

      container.cleanup

      expect(container).to be_empty
    end

    it 'clears the changeset' do
      container.mark_dirty(:username, :email)

      container.cleanup

      expect(container.changeset).to be_empty
    end

    it 'clears the observer reference' do
      _observer = container.observer

      container.cleanup

      expect(container.instance_variable_get(:@observer)).to be_nil
    end

    it 'handles cleanup when no delegators are present' do
      container[:username] = 'john_doe'
      container[:count] = 42

      expect { container.cleanup }.not_to raise_error
    end
  end
end
