# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LiveCable::Testing do
  include described_class

  describe 'live_mount' do
    it 'mounts a component by name' do
      counter = live_mount('counter')

      expect(counter.component).to be_a(Live::Counter)
      expect(counter.count).to eq(0)
    end

    it 'mounts a component by class' do
      counter = live_mount(Live::Counter, id: 'by-class')

      expect(counter.live_id).to eq('counter/by-class')
    end

    it 'applies defaults to reactive variables' do
      counter = live_mount('counter', count: 10, step: 5)

      expect(counter.count).to eq(10)
      expect(counter.step).to eq(5)
    end

    it 'broadcasts the initial render' do
      counter = live_mount('counter')

      expect(counter.broadcasts(:_refresh).size).to eq(1)
      expect(counter.rendered_html).to include('data-testid="counter-value"')
    end

    it 'runs connect lifecycle callbacks' do
      stream = live_mount('stream_test')

      expect(stream.channel.streams).to have_key('test_messages')
    end

    it 'exposes connection identifiers to the component' do
      user = Struct.new(:name).new('Jane')
      counter = live_mount('counter', identifiers: { current_user: user })

      expect(counter.current_user.name).to eq('Jane')
    end

    it 'works with non-live.erb templates' do
      component = live_mount('plain_erb')

      expect(component.rendered_html).to include('live-id')
    end

    it 'raises errors from the initial render by default' do
      expect do
        live_mount('error_on_subscribe')
      end.to raise_error(RuntimeError, 'Render error during subscribe')
    end

    it 'broadcasts errors from the initial render like production when raise_errors is false' do
      component = live_mount('error_on_subscribe', raise_errors: false)

      errors = component.broadcasts(:_error)
      expect(errors.size).to eq(1)
      expect(errors.first[:_error]).to include('Render error during subscribe')
    end

    it 'broadcasts errors from connect callbacks like production when raise_errors is false' do
      component_class = Class.new(LiveCable::Component) do
        def self.name = 'Live::ConnectErrorTest'

        after_connect { raise 'Connect error' }
      end

      component = live_mount(component_class, raise_errors: false)

      errors = component.broadcasts(:_error)
      expect(errors.size).to eq(1)
      expect(errors.first[:_error]).to include('Connect error')
    end
  end

  describe 'perform' do
    it 'dispatches whitelisted actions through the message pipeline' do
      counter = live_mount('counter')

      counter.perform(:increment)

      expect(counter.count).to eq(1)
    end

    it 'passes params as ActionController::Parameters with string values' do
      form = live_mount('form_test')

      form.perform(:update_form, user: { name: 'Alice', email: 'alice@example.com' })

      expect(form.user_name).to eq('Alice')
      expect(form.user_email).to eq('alice@example.com')
    end

    it 'supports nested params' do
      form = live_mount('form_test')

      form.perform(:update_form, user: { address_attributes: { street: '1 Elm St', city: 'Springfield' } })

      expect(form.address_street).to eq('1 Elm St')
      expect(form.address_city).to eq('Springfield')
    end

    it 'raises for actions that are not whitelisted' do
      counter = live_mount('counter')

      expect do
        counter.perform(:not_an_action)
      end.to raise_error(LiveCable::Error, /Unauthorized action/)
    end

    it 'raises errors from actions by default' do
      component = live_mount('error_test')

      expect do
        component.perform(:trigger_error)
      end.to raise_error(RuntimeError, 'Something went wrong')
    end

    it 'broadcasts errors like production when raise_errors is false' do
      component = live_mount('error_test', raise_errors: false)

      component.perform(:trigger_error)

      errors = component.broadcasts(:_error)
      expect(errors.size).to eq(1)
      expect(errors.first[:_error]).to include('Something went wrong')
    end

    it 're-renders after an action changes reactive variables' do
      counter = live_mount('counter')
      counter.clear_broadcasts

      counter.perform(:increment)

      expect(counter.broadcasts(:_refresh).size).to eq(1)
    end
  end

  describe 'set_reactive' do
    it 'updates writable reactive variables' do
      counter = live_mount('counter')

      counter.set_reactive(:step, '5')
      counter.perform(:increment)

      expect(counter.step).to eq('5')
      expect(counter.count).to eq(5)
    end

    it 'raises for non-writable reactive variables' do
      counter = live_mount('counter')

      expect do
        counter.set_reactive(:count, '999')
      end.to raise_error(LiveCable::Error, /Non-writable reactive variable/)
    end
  end

  describe 'rendered' do
    it 'reflects partial updates across renders' do
      counter = live_mount('counter')

      counter.perform(:increment)
      counter.perform(:increment)

      expect(counter.rendered).to have_css('[data-testid="counter-value"]', text: '2')
      # Static parts from the first render are still present
      expect(counter.rendered).to have_button('Reset')
    end

    it 'keeps the whole component after clear_broadcasts and an action' do
      counter = live_mount('counter')
      counter.clear_broadcasts

      counter.perform(:increment)

      expect(counter.rendered).to have_css('[data-testid="counter-value"]', text: '1')
      expect(counter.rendered).to have_button('Reset')
    end

    it 'keeps the whole component after clear_broadcasts and a stream broadcast' do
      stream = live_mount('stream_test')
      stream.receive_stream('test_messages', { text: 'hello' })
      stream.clear_broadcasts

      stream.receive_stream('test_messages', { text: 'world' })

      expect(stream.rendered).to have_css('[data-testid="stream-test"] li', count: 2)
    end

    it 'keeps inline children after clear_broadcasts' do
      parent = live_mount('parent')
      parent.clear_broadcasts

      parent.perform(:add)

      expect(parent.rendered).to have_css('[data-testid="children"] [data-testid="child-component"]', count: 2)
      expect(parent.rendered).to have_content('Child 0')
      expect(parent.rendered).to have_content('Child 1')
    end

    it 'resolves grandchildren rendered inline' do
      grandparent = live_mount('grandparent')

      expect(grandparent.rendered).to have_css('[data-testid="child-component"]', text: 'Child 0')
    end

    it 'keeps grandchildren from an earlier render' do
      grandparent = live_mount('grandparent')

      grandparent.perform(:rename, title: 'Elders')

      expect(grandparent.rendered).to have_css('h1', text: 'Elders')
      expect(grandparent.rendered).to have_css('[data-testid="child-component"]', text: 'Child 0')
    end
  end

  describe 'receive_stream' do
    it 'invokes the stream callback and re-renders' do
      stream = live_mount('stream_test')

      stream.receive_stream('test_messages', { text: 'hello' })
      stream.receive_stream('test_messages', { text: 'world' })

      expect(stream.messages).to eq(%w[hello world])
      expect(stream.rendered).to have_css('li', text: 'world')
    end

    it 'raises for streams the component is not subscribed to' do
      counter = live_mount('counter')

      expect do
        counter.receive_stream('nope', {})
      end.to raise_error(LiveCable::Error, /not streaming from "nope"/)
    end
  end

  describe 'shared state across components' do
    it 'shares reactive variables between components on the same connection' do
      first = live_mount('shared_counter', id: 'first')
      second = live_mount('shared_counter', id: 'second', connection: first.connection)

      first.clear_broadcasts
      second.clear_broadcasts

      first.perform(:bump)

      expect(first.total).to eq(1)
      expect(second.total).to eq(1)

      # Both components re-render when the shared variable changes
      expect(first.broadcasts(:_refresh).size).to eq(1)
      expect(second.broadcasts(:_refresh).size).to eq(1)
    end
  end

  describe 'unmount' do
    it 'disconnects the component and cleans up' do
      counter = live_mount('counter')
      live_id = counter.live_id

      counter.unmount

      expect(counter.connection.get_component(live_id)).to be_nil
      expect(counter.channel.streams).to be_empty
    end
  end
end
