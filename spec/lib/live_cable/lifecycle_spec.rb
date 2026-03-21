# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LiveCable::Component::Lifecycle do
  let(:component_class) do
    Class.new(LiveCable::Component) do
      def self.name = 'Live::LifecycleTest'

      reactive :value, -> { 'initial' }

      def to_partial_path = 'lifecycle_test'
    end
  end

  let(:connection) { LiveCable::Connection.new(double('request', session: {})) }
  let(:channel) { instance_double(ActionCable::Channel::Base) }
  let(:component) do
    component_class.new('test-id').tap do |c|
      c.live_connection = connection
      connection.add_component(c)
    end
  end

  describe '#connect' do
    before do
      allow(component).to receive(:broadcast)
      allow(component).to receive(:channel_name).and_return('test_channel')
      allow(channel).to receive(:stream_from)
    end

    it 'marks the component as subscribed' do
      component.connect(channel)

      expect(component.subscribed?).to be true
    end

    it 'runs connect callbacks' do
      called = false
      component_class.before_connect { called = true }

      component.connect(channel)

      expect(called).to be true
    ensure
      component_class.reset_callbacks(:connect)
    end
  end

  describe '#disconnect' do
    before do
      allow(component).to receive(:broadcast)
      allow(component).to receive(:channel_name).and_return('test_channel')
      allow(channel).to receive(:stream_from)
      allow(channel).to receive(:stop_stream_from)
      component.connect(channel)
    end

    it 'removes the component from the connection' do
      live_id = component.live_id
      component.disconnect

      expect(connection.get_component(live_id)).to be_nil
    end

    it 'clears the live_connection reference' do
      component.disconnect

      expect(component.live_connection).to be_nil
    end

    it 'runs disconnect callbacks' do
      called = false
      component_class.before_disconnect { called = true }

      component.disconnect

      expect(called).to be true
    ensure
      component_class.reset_callbacks(:disconnect)
    end
  end

  describe '#destroy' do
    before do
      allow(component).to receive(:broadcast)
    end

    it 'broadcasts a destroy status' do
      expect(component).to receive(:broadcast).with({ _status: 'destroy' })

      component.destroy
    end

    it 'marks the component as not subscribed' do
      component.destroy

      expect(component.subscribed?).to be false
    end

    it 'cascades destroy to rendered children' do
      child = double('child')
      allow(component).to receive(:previous_render_context).and_return(
        double('context', children: [child])
      )

      expect(child).to receive(:destroy)

      component.destroy
    end
  end
end
