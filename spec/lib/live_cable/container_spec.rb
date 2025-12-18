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
end
