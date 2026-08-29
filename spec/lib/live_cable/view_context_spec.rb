# frozen_string_literal: true

require 'rails_helper'
require 'action_dispatch/testing/test_request'

RSpec.describe 'View contexts for socket renders' do
  include LiveCable::Testing

  let(:connection) { LiveCable::Connection.new(ActionDispatch::TestRequest.create('rack.session' => {})) }

  it 'keeps one request per connection' do
    expect(connection.view_context.request).to equal(connection.view_context.request)
  end

  it 'gives every render a fresh controller and view' do
    first = connection.view_context
    second = connection.view_context

    expect(second).not_to equal(first)
    expect(second.controller).not_to equal(first.controller)
  end

  it "builds the request from ApplicationController.renderer's defaults" do
    allow(ApplicationController).to receive(:renderer).
      and_return(ApplicationController.renderer.with_defaults(http_host: 'live.example.org', https: true))

    expect(connection.view_context.request.base_url).to eq('https://live.example.org')
  end

  it 'builds a new request after a code reload replaces ApplicationController' do
    request = connection.view_context.request
    stub_const('ApplicationController', Class.new(ApplicationController))
    view = connection.view_context

    expect(view.controller).to be_an_instance_of(ApplicationController)
    expect(view.request).not_to equal(request)
  end

  it 'renders components sharing a connection correctly, render after render' do
    counter = live_mount('counter', step: 3)
    other = live_mount('hidden_var', id: 'h', connection: counter.connection)

    2.times { counter.perform(:increment) }
    other.perform(:bump_shown)

    expect(counter.rendered).to have_css('[data-testid="counter-value"]', text: '6')
    expect(other.rendered).to have_css('[data-testid="shown"]', text: '1')
  end

  it 'renders a component that defines a format method' do
    component = live_mount('format_method')
    component.perform(:bump)

    expect(component.rendered).to have_css('[data-testid="format"]', text: 'long 1')
  end

  context 'when the locale changes during a connection' do
    around do |example|
      available = I18n.available_locales
      I18n.available_locales = %i[en fr]
      example.run
    ensure
      I18n.available_locales = available
    end

    it 'reads default_url_options on every render' do
      localized_urls = Class.new(ApplicationController) do
        def default_url_options = { locale: I18n.locale }
      end
      stub_const('ApplicationController', localized_urls)

      component = live_mount('localized')
      I18n.with_locale(:fr) { component.perform(:bump) }

      expect(component.rendered).to have_css('[data-testid="link"][href="/counter?locale=fr"]', text: '1')
    end

    it 'picks localized templates in the locale of each render' do
      component = live_mount('localized')
      expect(component.rendered).to have_css('[data-testid="greeting"]', text: '0 hello')

      I18n.with_locale(:fr) { component.perform(:bump) }

      expect(component.rendered).to have_css('[data-testid="greeting"]', text: '1 bonjour')
    end
  end
end
