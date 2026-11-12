# frozen_string_literal: true

require 'rails_helper'
require 'action_dispatch/testing/test_request'

RSpec.describe 'View contexts for socket renders' do
  include LiveCable::Testing

  def socket_request(env = {})
    ActionDispatch::TestRequest.create({ 'rack.session' => ActionController::TestSession.new }.merge(env))
  end

  def raising(connection)
    def connection.handle_error(_component, error, **)
      raise error
    end

    connection
  end

  let(:connection) { LiveCable::Connection.new(socket_request) }

  it 'keeps one request per connection' do
    expect(connection.view_context.request).to equal(connection.view_context.request)
  end

  it 'gives every render a fresh controller and view' do
    first = connection.view_context
    second = connection.view_context

    expect(second).not_to equal(first)
    expect(second.controller).not_to equal(first.controller)
  end

  it "builds the request from the socket's host and protocol" do
    connection = LiveCable::Connection.new(socket_request('HTTP_HOST' => 'shop.test', 'HTTPS' => 'on'))

    expect(connection.view_context.root_url).to eq('https://shop.test/')
  end

  it "builds the request from the application's script name, not the socket's path" do
    request = socket_request('SCRIPT_NAME' => '/shop', 'PATH_INFO' => '/cable', 'ORIGINAL_SCRIPT_NAME' => '/shop')
    view = LiveCable::Connection.new(request).view_context

    expect(view.root_path).to eq('/shop/')
    expect(view.request.path).to eq('/shop')
  end

  it "ignores ApplicationController.renderer's defaults" do
    allow(ApplicationController).to receive(:renderer).
      and_return(ApplicationController.renderer.with_defaults(http_host: 'live.example.org', https: true))

    expect(connection.view_context.request.base_url).to eq('http://test.host')
  end

  it "reads the socket's session" do
    session = ActionController::TestSession.new(user_id: 7)
    connection = LiveCable::Connection.new(socket_request('rack.session' => session))

    expect(connection.view_context.session[:user_id]).to eq(7)
  end

  it 'keeps what middleware put on the socket\'s request' do
    warden = Object.new
    connection = LiveCable::Connection.new(socket_request('warden' => warden))

    expect(connection.view_context.request.env['warden']).to equal(warden)
  end

  context 'with forgery protection on' do
    around do |example|
      forgery = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      example.run
    ensure
      ActionController::Base.allow_forgery_protection = forgery
    end

    it "renders forms with an authenticity token the socket's session accepts" do
      session = ActionController::TestSession.new(_csrf_token: SecureRandom.urlsafe_base64(32))
      connection = raising(LiveCable::Connection.new(socket_request('rack.session' => session)))

      form = live_mount('page_context', connection:).rendered.find('form')
      token = form.find('input[name="authenticity_token"]', visible: :all).value

      post = socket_request('REQUEST_METHOD' => 'POST', 'PATH_INFO' => form[:action], 'rack.session' => session)
      post.request_parameters = { 'authenticity_token' => token }
      controller = ApplicationController.new.tap { |instance| instance.set_request!(post) }

      expect(controller.send(:verified_request?)).to be(true)
    end

    it 'renders forms with an authenticity token in the harness, as on a socket' do
      component = live_mount('page_context')

      expect(component.rendered).to have_css('input[name="authenticity_token"]', visible: :all)
    end
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
