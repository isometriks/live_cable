# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LiveChannel, type: :channel do
  let(:live_connection) { LiveCable::Connection.new(ActionDispatch::TestRequest.create) }

  before do
    stub_connection(live_connection:)
  end

  # Build the component as normal, then make one of its methods raise
  def build_component_that_fails(method, message)
    allow(LiveCable).to receive(:instance_from_string).and_wrap_original do |original, *args|
      original.call(*args).tap do |component|
        allow(component).to receive(method).and_raise(RuntimeError, message)
      end
    end
  end

  describe '#subscribed' do
    it 'renders the component' do
      subscribe(component: 'counter', id: 'c1')

      expect(subscription).to be_confirmed
      expect(transmissions.last).to have_key('_refresh')
    end

    it 'renders the component for the path the client subscribes from' do
      subscribe(component: 'page_context', id: 'p1', path: '/page_context?q=shoes')

      html = transmissions.last['_refresh']['p'].join
      expect(html).to include('href="/page_context?page=2"', '<span data-testid="query">shoes</span>')
    end

    it 'marks the frame it sends as the subscribe' do
      subscribe(component: 'counter', id: 'c1')

      expect(transmissions.last).to include('_subscribed' => true, '_reply' => false)
    end

    it 'marks the status it sends for a component its parent already rendered' do
      subscribe(component: 'todo_list', id: 'list')
      subscribe(component: 'todo', id: 'write')

      expect(transmissions.last).to include('_status' => 'subscribed', '_subscribed' => true)
    end

    it 'transmits an _error when no component could be built' do
      allow(Rails.error).to receive(:report)

      subscribe(component: 'no_such_component', id: 'c1')

      expect(Rails.error).to have_received(:report).with(an_instance_of(LiveCable::Error))
      expect(transmissions.last['_error']).to include('LiveCable::Error')
    end

    it 'transmits an _error when the component fails before it has a channel' do
      allow(Rails.error).to receive(:report)
      build_component_that_fails(:apply_defaults, 'bad default')

      subscribe(component: 'counter', id: 'c1')

      expect(transmissions.last['_error']).to include('bad default')
    end

    it 'transmits an _error when the component fails to load with a SyntaxError' do
      allow(Rails.error).to receive(:report)
      allow(LiveCable).to receive(:instance_from_string).and_raise(SyntaxError, 'unexpected end-of-input')

      expect { subscribe(component: 'counter', id: 'c1') }.not_to raise_error

      expect(transmissions.last['_error']).to include('unexpected end-of-input')
    end

    it 'transmits only an _error when an initial value fails' do
      allow(Rails.error).to receive(:report)

      subscribe(component: 'failing_initial', id: 'f1')

      expect(transmissions.map(&:keys)).to eq([['_error']])
    end

    it 'lets the client unsubscribe clean up a component whose subscribe failed' do
      allow(Rails.error).to receive(:report)
      build_component_that_fails(:broadcast_render, 'bad template')

      subscribe(component: 'counter', id: 'c1')
      expect(live_connection.get_component('counter/c1')).to be_present

      unsubscribe

      expect(live_connection.get_component('counter/c1')).to be_nil
    end

    it 'refuses a connection whose live_connection is shadowed by a leftover identified_by' do
      stub_connection(live_connection: nil)

      expect do
        subscribe(component: 'counter', id: 'c1')
      end.to raise_error(LiveCable::Error, /identified_by :live_connection/)
    end

    # Live::Counter marks only :step writable; :count is server-only
    it 'applies defaults the server signed for this component' do
      subscribe(component: 'counter', id: 'c1',
        defaults: LiveCable::DefaultsSigner.sign({ count: 7 }, 'counter/c1'))

      expect(live_connection.get_component('counter/c1').count).to eq(7)
    end

    it 'lets an initial lambda read the signed defaults' do
      subscribe(component: 'default_reader', id: 'r1',
        defaults: LiveCable::DefaultsSigner.sign({ owner_id: 7 }, 'default_reader/r1'))

      expect(live_connection.get_component('default_reader/r1').user_id).to eq(7)
    end

    it 'ignores defaults the client sent unsigned, so a non-writable variable stays put' do
      subscribe(component: 'counter', id: 'c1', defaults: { count: 999 })

      expect(live_connection.get_component('counter/c1').count).to eq(0)
    end

    it "ignores another component's signed defaults replayed onto this one" do
      subscribe(component: 'counter', id: 'c1',
        defaults: LiveCable::DefaultsSigner.sign({ count: 999 }, 'counter/c2'))

      expect(live_connection.get_component('counter/c1').count).to eq(0)
    end

    it 'subscribes with the defaults the prerender used' do
      html = ApplicationController.render(inline: "<%= live('default_kind', id: 'k1', kind: :open) %>")
      span = Capybara.string(html).find('[data-testid="kind"]')

      subscribe(component: 'default_kind', id: 'k1', defaults: span['live-defaults'])

      expect(span.text).to eq('"open"')
      expect(live_connection.get_component('default_kind/k1').kind).to eq('open')
    end

    it 'prerenders children with the values their parent passed' do
      html = ApplicationController.render(inline: "<%= live('sharing_parent', id: 'p') %>")

      expect(Capybara.string(html)).to have_css('[data-testid="row-done"]', exact_text: 'false', count: 2)
    end
  end

  describe 'replacing a subscription' do
    # A client re-subscribes a component whose defaults changed by
    # unsubscribing the old subscription and creating a new one
    def subscribe_with_count(count)
      subscribe(component: 'counter', id: 'c1',
        defaults: LiveCable::DefaultsSigner.sign({ count: }, 'counter/c1'))
      subscription
    end

    it 'builds a fresh component when the old subscription is gone first' do
      subscribe_with_count(1).unsubscribe_from_channel

      subscribe_with_count(2)

      expect(live_connection.get_component('counter/c1').count).to eq(2)
    end

    it 'replaces the component when the new subscribe is processed before the old unsubscribe' do
      old = subscribe_with_count(1)
      old_component = live_connection.get_component('counter/c1')
      allow(old_component).to receive(:disconnect).and_call_original

      subscribe_with_count(2)
      old.unsubscribe_from_channel

      expect(live_connection.get_component('counter/c1')).not_to equal(old_component)
      expect(live_connection.get_component('counter/c1').count).to eq(2)
      expect(old_component).to have_received(:disconnect).once
    end
  end

  describe 'rebuilding a parent from new defaults' do
    def subscribe_shell(account)
      subscribe(component: 'shell', id: 'shell',
        defaults: LiveCable::DefaultsSigner.sign({ account: }, 'shell/shell'))
      subscription
    end

    def child_render
      transmissions.reverse.find { |frame| frame['_subscribed'] }.dig('_refresh', 'c', 'counter/shell-child', 'p')
    end

    let!(:old_shell) { subscribe_shell(1) }
    let!(:old_child) do
      subscribe(component: 'counter', id: 'shell-child')
      subscription.perform_action('action' => 'receive', 'messages' => [{ '_action' => 'increment' }])
      subscription
    end

    it 'builds its children again when their unsubscribes arrive after its new subscribe' do
      old_shell.unsubscribe_from_channel
      subscribe_shell(5)
      old_child.unsubscribe_from_channel

      expect(child_render).to all(be_a(String))
      expect(live_connection.get_component('counter/shell-child').count).to eq(5)
    end

    it 'builds its children again when its new subscribe arrives before every unsubscribe' do
      subscribe_shell(5)
      old_shell.unsubscribe_from_channel
      old_child.unsubscribe_from_channel

      expect(child_render).to all(be_a(String))
      expect(live_connection.get_component('counter/shell-child').count).to eq(5)
    end
  end

  describe 'the children of a parent that disconnects' do
    it 'are disconnected when a failed render of the parent destroyed them' do
      host = subscribe(component: 'toggle_host', id: 'toggle') && subscription
      child = subscribe(component: 'counter', id: 'toggled') && subscription
      destroyed = live_connection.get_component('counter/toggled')
      allow(destroyed).to receive(:disconnect).and_call_original

      live_connection.handle_error(live_connection.get_component('toggle_host/toggle'), RuntimeError.new('boom'))
      host.unsubscribe_from_channel
      child.unsubscribe_from_channel

      expect(destroyed).to have_received(:disconnect).once
    end
  end

  describe 'a child its parent stops rendering' do
    def flip(host)
      host.perform_action('action' => 'receive', 'messages' => [{ '_action' => 'flip' }])
    end

    it 'is disconnected once, and its late unsubscribe leaves the child shown again alone' do
      host = subscribe(component: 'toggle_host', id: 'toggle') && subscription
      child = subscribe(component: 'counter', id: 'toggled') && subscription
      destroyed = live_connection.get_component('counter/toggled')
      allow(destroyed).to receive(:disconnect).and_call_original

      flip(host)
      flip(host)
      child.unsubscribe_from_channel

      expect(destroyed).to have_received(:disconnect).once
      expect(live_connection.get_component('counter/toggled')).to be_present
      expect(live_connection.get_component('counter/toggled')).not_to equal(destroyed)
    end

    it 'ignores a message the destroyed child sent before the destroy reached it' do
      host = subscribe(component: 'toggle_host', id: 'toggle') && subscription
      child = subscribe(component: 'counter', id: 'toggled') && subscription
      destroyed = live_connection.get_component('counter/toggled')
      allow(destroyed).to receive(:perform_dispatch).and_call_original
      flip(host)
      connection.transmissions.clear

      child.perform_action('action' => 'receive', 'messages' => [{ '_action' => 'increment' }])

      expect(destroyed).not_to have_received(:perform_dispatch)
      expect(transmissions).to eq([{ '_status' => 'destroy' }])
    end

    it 'is disconnected when it was destroyed before its parent dropped it' do
      host = subscribe(component: 'toggle_host', id: 'toggle') && subscription
      child = subscribe(component: 'counter', id: 'toggled') && subscription
      destroyed = live_connection.get_component('counter/toggled')
      allow(destroyed).to receive(:disconnect).and_call_original

      destroyed.destroy
      flip(host)
      child.unsubscribe_from_channel

      expect(destroyed).to have_received(:disconnect).once
    end
  end

  describe '#receive' do
    it 'answers a message batch' do
      subscribe(component: 'counter', id: 'c1')
      connection.transmissions.clear

      perform(:receive, messages: [{ '_action' => 'increment' }])

      expect(transmissions.size).to eq(1)
      expect(transmissions.last).to have_key('_refresh')
    end

    it 'transmits an _error instead of raising when there is no component' do
      allow(Rails.error).to receive(:report)
      subscribe(component: 'no_such_component', id: 'c1')
      connection.transmissions.clear

      expect do
        perform(:receive, messages: [{ '_action' => 'increment' }])
      end.not_to raise_error

      expect(transmissions.size).to eq(1)
      expect(transmissions.last['_error']).to include('cannot receive messages')
    end

    it 'transmits an _error instead of raising when an action raises NotImplementedError' do
      allow(Rails.error).to receive(:report)
      subscribe(component: 'counter', id: 'c1')
      connection.transmissions.clear
      component = live_connection.get_component('counter/c1')
      allow(component).to receive(:increment).and_raise(NotImplementedError, 'abstract')

      expect do
        perform(:receive, messages: [{ '_action' => 'increment' }])
      end.not_to raise_error

      expect(transmissions.size).to eq(1)
      expect(transmissions.last['_error']).to include('abstract')
    end

    it 'transmits an _error instead of raising when the connection raises' do
      allow(Rails.error).to receive(:report)
      subscribe(component: 'counter', id: 'c1')
      connection.transmissions.clear
      allow(live_connection).to receive(:receive).and_raise(RuntimeError, 'boom')

      expect do
        perform(:receive, messages: [{ '_action' => 'increment' }])
      end.not_to raise_error

      expect(transmissions.size).to eq(1)
      expect(transmissions.last['_error']).to include('boom')
    end
  end
end
