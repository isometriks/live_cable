# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LiveCable::Connection do
  let(:session) { {} }
  let(:request) { double('request', session:) }
  let(:connection) { described_class.new(request) }

  let(:component_class) do
    Class.new(LiveCable::Component) do
      def self.name = 'Live::TestConnection'

      reactive :count, -> { 0 }
      reactive :visible, -> { true }
      reactive :name, -> { 'default' }, writable: true

      actions :increment, :toggle, :failing_action

      def increment
        self.count += 1
      end

      def toggle
        self.visible = !visible
      end

      def failing_action
        raise 'Action failed'
      end

      def to_partial_path = 'test_connection'
    end
  end

  let(:component) do
    component_class.new('test-id').tap do |c|
      c.live_connection = connection
      connection.add_component(c)
    end
  end

  describe 'ComponentManagement' do
    it 'adds and retrieves a component' do
      expect(connection.get_component(component.live_id)).to eq(component)
    end

    it 'removes a component and cleans up its container' do
      live_id = component.live_id
      # Access a variable to ensure container exists
      component.count

      connection.remove_component(component)

      expect(connection.get_component(live_id)).to be_nil
    end

    it 'cleans up shared container when last component is removed' do
      connection.remove_component(component)

      containers = connection.send(:containers)
      expect(containers).not_to have_key(LiveCable::Connection::SHARED_CONTAINER)
    end
  end

  describe 'StateManagement' do
    it 'gets initial value from a proc' do
      value = connection.get(component.live_id, component, :count, -> { 0 })

      expect(value).to eq(0)
    end

    it 'returns stored value on subsequent gets' do
      connection.get(component.live_id, component, :count, -> { 0 })
      connection.set(component.live_id, :count, 42)

      value = connection.get(component.live_id, component, :count, -> { 0 })

      expect(value).to eq(42)
    end

    it 'handles falsy stored values correctly' do
      connection.get(component.live_id, component, :visible, -> { true })
      connection.set(component.live_id, :visible, false)

      value = connection.get(component.live_id, component, :visible, -> { true })

      expect(value).to be false
    end

    it 'handles nil initial values' do
      value = connection.get(component.live_id, component, :optional, nil)

      expect(value).to be_nil
    end

    it 'passes component to proc when arity is positive' do
      initial = ->(comp) { "hello #{comp.class.name}" }
      value = connection.get(component.live_id, component, :greeting, initial)

      expect(value).to eq('hello Live::TestConnection')
    end

    it 'handles non-proc, non-nil initial values via error handler' do
      allow(Rails).to receive(:error).and_return(double(report: nil))
      allow(component).to receive(:broadcast)
      allow(component).to receive(:rendered_children).and_return([])

      # process_initial_value rescues and calls handle_error instead of raising
      result = connection.get(component.live_id, component, :bad, 'not a proc')

      expect(result).to be_nil
    end

    it 'marks variable dirty on set' do
      component.count # initialize the container
      connection.send(:reset_changeset)

      connection.set(component.live_id, :count, 5)

      changeset = connection.changeset_for(component)
      expect(changeset).to include(:count)
    end

    it 'computes changeset including shared reactive variables' do
      shared_class = Class.new(LiveCable::Component) do
        def self.name = 'Live::SharedTest'
        reactive :shared_val, -> { 0 }, shared: true
        reactive :local_val, -> { 0 }
        def to_partial_path = 'shared_test'
      end

      comp = shared_class.new('shared-id')
      comp.live_connection = connection
      connection.add_component(comp)

      comp.shared_val
      comp.local_val
      connection.send(:reset_changeset)

      connection.set(LiveCable::Connection::SHARED_CONTAINER, :shared_val, 1)

      changeset = connection.changeset_for(comp)
      expect(changeset).to include(:shared_val)
    end
  end

  describe 'Messaging' do
    let(:channel) { instance_double(ActionCable::Channel::Base) }

    before do
      allow(component).to receive(:broadcast)
      allow(component).to receive(:channel_name).and_return('test_channel')
      allow(channel).to receive(:stream_from)
      allow(connection).to receive(:broadcast_changeset)
      component.connect(channel)
    end

    it 'dispatches an action to the component' do
      connection.receive(component, {
        'messages' => [{ '_action' => 'increment' }],
      })

      expect(component.count).to eq(1)
    end

    it 'dispatches multiple messages in order' do
      connection.receive(component, {
        'messages' => [
          { '_action' => 'increment' },
          { '_action' => 'increment' },
          { '_action' => 'increment' },
        ],
      })

      expect(component.count).to eq(3)
    end

    it 'handles reactive variable updates' do
      connection.receive(component, {
        'messages' => [{ '_action' => '_reactive', 'name' => 'name', 'value' => 'alice' }],
      })

      expect(component.name).to eq('alice')
    end

    it 'handles unauthorized actions via error handler' do
      allow(Rails).to receive(:error).and_return(double(report: nil))
      allow(component).to receive(:rendered_children).and_return([])

      connection.receive(component, {
        'messages' => [{ '_action' => 'not_allowed' }],
      })

      # The error is handled internally, not raised
    end

    it 'handles invalid reactive variable names via error handler' do
      allow(Rails).to receive(:error).and_return(double(report: nil))
      allow(component).to receive(:rendered_children).and_return([])

      connection.receive(component, {
        'messages' => [{ '_action' => '_reactive', 'name' => 'nonexistent', 'value' => 'x' }],
      })
    end

    it 'rejects reactive variable updates for non-writable variables' do
      allow(Rails).to receive(:error).and_return(double(report: nil))
      allow(component).to receive(:rendered_children).and_return([])

      connection.receive(component, {
        'messages' => [{ '_action' => '_reactive', 'name' => 'count', 'value' => '999' }],
      })

      expect(component.count).to eq(0)
    end

    it 'skips processing when no messages present' do
      expect do
        connection.receive(component, {})
      end.not_to raise_error
    end

    it 'validates CSRF token when session has one' do
      session[:_csrf_token] = 'real_token'

      expect do
        connection.receive(component, {
          '_csrf_token' => 'wrong_token',
          'messages' => [{ '_action' => 'increment' }],
        })
      end.to raise_error(LiveCable::Error, /Invalid CSRF token/)
    end

    it 'skips CSRF validation when session has no token' do
      expect do
        connection.receive(component, {
          'messages' => [{ '_action' => 'increment' }],
        })
      end.not_to raise_error
    end
  end

  describe 'ErrorHandling' do
    before do
      allow(Rails).to receive(:error).and_return(double(report: nil))
      allow(component).to receive(:broadcast)
      allow(component).to receive(:rendered_children).and_return([])
    end

    it 'reports the error to Rails.error' do
      error_reporter = double('error_reporter')
      allow(Rails).to receive(:error).and_return(error_reporter)
      expect(error_reporter).to receive(:report).with(an_instance_of(RuntimeError))

      connection.handle_error(component, RuntimeError.new('test'))
    end

    it 'broadcasts an error with verbose details in non-production' do
      allow(LiveCable.configuration).to receive(:verbose_errors).and_return(true)

      expect(component).to receive(:broadcast) do |data|
        expect(data[:_error]).to include('RuntimeError')
        expect(data[:_error]).to include('test error message')
      end

      connection.handle_error(component, RuntimeError.new('test error message'))
    end

    it 'broadcasts a generic error message in production' do
      allow(LiveCable.configuration).to receive(:verbose_errors).and_return(false)

      expect(component).to receive(:broadcast) do |data|
        expect(data[:_error]).to include('An error occurred')
        expect(data[:_error]).not_to include('RuntimeError')
      end

      connection.handle_error(component, RuntimeError.new('secret details'))
    end

    it 'destroys rendered children before broadcasting the error' do
      child = double('child')
      allow(component).to receive(:rendered_children).and_return([child])

      expect(child).to receive(:destroy).ordered
      expect(component).to receive(:broadcast).ordered

      connection.handle_error(component, RuntimeError.new('test'))
    end
  end

  describe 'Broadcasting' do
    let(:channel) { instance_double(ActionCable::Channel::Base) }

    before do
      allow(component).to receive(:broadcast)
      allow(component).to receive(:channel_name).and_return('test_channel')
      allow(channel).to receive(:stream_from)
      component.connect(channel)
    end

    it 'broadcasts to components with dirty changesets' do
      component.count # initialize
      connection.send(:reset_changeset)
      connection.set(component.live_id, :count, 5)

      expect(component).to receive(:broadcast_render)

      connection.broadcast_changeset
    end

    it 'skips components without changes' do
      component.count # initialize
      connection.send(:reset_changeset)

      expect(component).not_to receive(:broadcast_render)

      connection.broadcast_changeset
    end

    it 'handles errors during broadcast_render' do
      allow(Rails).to receive(:error).and_return(double(report: nil))
      allow(component).to receive(:rendered_children).and_return([])

      component.count
      connection.send(:reset_changeset)
      connection.set(component.live_id, :count, 5)

      allow(component).to receive(:broadcast_render).and_raise(RuntimeError, 'render failed')

      expect do
        connection.broadcast_changeset
      end.not_to raise_error
    end
  end
end
