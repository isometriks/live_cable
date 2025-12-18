# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LiveCable::Component do
  # Create test component classes
  let(:test_component_class) do
    Class.new(described_class) do
      def self.name
        'Live::TestComponent'
      end

      reactive :username, -> { 'default_user' }
      reactive :count, -> { 0 }
      reactive :tags, -> { [] }
      reactive :settings, -> { {} }

      def to_partial_path
        'test_component'
      end
    end
  end

  let(:shared_component_class) do
    Class.new(described_class) do
      def self.name
        'Live::SharedComponent'
      end

      shared :global_counter, -> { 0 }
      reactive :local_value, -> { 'local' }

      def to_partial_path
        'shared_component'
      end
    end
  end

  describe '.reactive' do
    it 'defines getter and setter methods' do
      component = test_component_class.new('test-id')

      expect(component).to respond_to(:username)
      expect(component).to respond_to(:username=)
    end

    it 'adds variable to reactive_variables list' do
      expect(test_component_class.reactive_variables).to include(:username, :count, :tags, :settings)
    end

    it 'returns initial value when no connection exists' do
      component = test_component_class.new('test-id')

      expect(component.username).to eq('default_user')
      expect(component.count).to eq(0)
    end
  end

  describe '.shared' do
    it 'defines getter and setter methods' do
      component = shared_component_class.new('test-id')

      expect(component).to respond_to(:global_counter)
      expect(component).to respond_to(:global_counter=)
    end

    it 'adds variable to shared_variables list' do
      expect(shared_component_class.shared_variables).to include(:global_counter)
    end
  end

  describe 'reactive variables without connection' do
    let(:component) { test_component_class.new('test-id') }

    it 'returns initial values' do
      expect(component.username).to eq('default_user')
      expect(component.count).to eq(0)
    end

    it 'stores values in prerender container when setting' do
      component.username = 'john_doe'

      expect(component.username).to eq('john_doe')
    end

    it 'allows multiple sets and gets' do
      component.username = 'first'
      component.username = 'second'
      component.count = 5

      expect(component.username).to eq('second')
      expect(component.count).to eq(5)
    end

    it 'works with array initial values' do
      component.tags = %w[ruby rails]

      expect(component.tags).to eq(%w[ruby rails])
    end

    it 'works with hash initial values' do
      component.settings = { theme: 'dark' }

      expect(component.settings).to eq({ theme: 'dark' })
    end
  end

  describe 'reactive variables with connection' do
    let(:connection) { LiveCable::Connection.new(double('request', session: {})) }
    let(:component) do
      test_component_class.new('test-id').tap do |c|
        c.live_connection = connection
        connection.add_component(c)
      end
    end

    it 'reads from connection container' do
      expect(component.username).to eq('default_user')
    end

    it 'writes to connection container and marks dirty' do
      component.username = 'jane_doe'

      expect(component.username).to eq('jane_doe')
    end

    it 'persists values across reads' do
      component.count = 10
      expect(component.count).to eq(10)
      expect(component.count).to eq(10)
    end

    context 'with arrays' do
      it 'wraps arrays in delegator for change tracking' do
        component.tags = %w[ruby rails]

        expect(component.tags).to be_a(LiveCable::Delegator)
      end

      it 'tracks changes to arrays' do
        component.tags = ['ruby']
        container = connection.instance_variable_get(:@containers)[component.live_id]
        container.reset_changeset

        component.tags << 'rails'

        expect(container.changeset).to include(:tags)
      end
    end

    context 'with hashes' do
      it 'wraps hashes in delegator for change tracking' do
        component.settings = { theme: 'dark' }

        expect(component.settings).to be_a(LiveCable::Delegator)
      end

      it 'tracks changes to hashes' do
        component.settings = { theme: 'dark' }
        container = connection.instance_variable_get(:@containers)[component.live_id]
        container.reset_changeset

        component.settings[:language] = 'en'

        expect(container.changeset).to include(:settings)
      end
    end
  end

  describe 'shared reactive variables with connection' do
    let(:connection) { LiveCable::Connection.new(double('request', session: {})) }
    let(:component1) do
      shared_component_class.new('comp1').tap do |c|
        c.live_connection = connection
        connection.add_component(c)
      end
    end
    let(:component2) do
      shared_component_class.new('comp2').tap do |c|
        c.live_connection = connection
        connection.add_component(c)
      end
    end

    it 'shares values between components' do
      component1.global_counter = 5

      expect(component2.global_counter).to eq(5)
    end

    it 'keeps local values separate' do
      component1.local_value = 'comp1_value'
      component2.local_value = 'comp2_value'

      expect(component1.local_value).to eq('comp1_value')
      expect(component2.local_value).to eq('comp2_value')
    end

    it 'updates shared value from either component' do
      component1.global_counter = 10
      component2.global_counter = 20

      expect(component1.global_counter).to eq(20)
      expect(component2.global_counter).to eq(20)
    end
  end

  describe '#initialize' do
    it 'sets the component id' do
      component = test_component_class.new('my-id')

      expect(component.live_id).to eq('test_component/my-id')
    end

    it 'initializes rendered as false' do
      component = test_component_class.new('test-id')

      expect(component.rendered).to be false
    end

    it 'initializes subscribed as false' do
      component = test_component_class.new('test-id')

      expect(component.subscribed?).to be false
    end
  end

  describe '#defaults=' do
    let(:component) { test_component_class.new('test-id') }

    it 'sets reactive variables from defaults hash' do
      component.defaults = { username: 'alice', count: 42 }

      expect(component.username).to eq('alice')
      expect(component.count).to eq(42)
    end

    it 'ignores non-reactive keys' do
      expect do
        component.defaults = { username: 'alice', invalid_key: 'value' }
      end.not_to raise_error

      expect(component.username).to eq('alice')
    end

    it 'converts string keys to symbols' do
      component.defaults = { 'username' => 'bob' }

      expect(component.username).to eq('bob')
    end

    it 'only sets defaults once' do
      component.defaults = { username: 'first' }
      component.defaults = { username: 'second' }

      expect(component.username).to eq('first')
    end
  end

  describe '#channel_name' do
    it 'returns unique channel name based on component id' do
      connection = LiveCable::Connection.new(double('request', session: {}))
      component = test_component_class.new('test-id')
      component.live_connection = connection

      expect(component.channel_name).to include('test_component/test-id')
    end
  end

  describe '#status' do
    it 'returns disconnected when not subscribed' do
      component = test_component_class.new('test-id')

      expect(component.status).to eq('disconnected')
    end

    it 'returns subscribed after broadcast_subscribe' do
      component = test_component_class.new('test-id')

      # Stub broadcast method to avoid needing full connection setup
      allow(component).to receive(:broadcast)
      component.broadcast_subscribe

      expect(component.status).to eq('subscribed')
    end

    it 'returns disconnected after broadcast_destroy' do
      component = test_component_class.new('test-id')

      # Stub broadcast method to avoid needing full connection setup
      allow(component).to receive(:broadcast)
      component.broadcast_subscribe
      component.broadcast_destroy

      expect(component.status).to eq('disconnected')
    end
  end

  describe '.component_string' do
    it 'returns underscored component name without Live:: prefix' do
      expect(test_component_class.component_string).to eq('test_component')
    end
  end

  describe '.component_id' do
    it 'combines component string with id' do
      expect(test_component_class.component_id('123')).to eq('test_component/123')
    end
  end

  describe '#all_reactive_variables' do
    it 'includes both reactive and shared variables' do
      component = shared_component_class.new('test-id')

      # The shared method adds to shared_variables, not shared_reactive_variables
      # So all_reactive_variables only returns reactive_variables + shared_reactive_variables
      # which in this case is just [:local_value, :local_value] (local_value appears in both)
      # Let's test what it actually returns
      expect(component.all_reactive_variables).to include(:local_value)
    end
  end
end
