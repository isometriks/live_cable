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

  it 'gives every render a fresh request and response' do
    first = connection.view_context('/counter')
    second = connection.view_context('/counter')

    expect(second.request).not_to equal(first.request)
    expect(second.response).not_to equal(first.response)
  end

  it 'lets no render see request state an earlier render or another component set' do
    marker = live_mount('request_marker', id: 'a')
    other = live_mount('request_marker', id: 'b', connection: marker.connection)
    marker.perform(:bump)

    expect(other.rendered).to have_css('[data-testid="seen"]', text: '1')
    expect(marker.rendered).to have_css('[data-testid="seen"]', text: '1')
    expect(marker.rendered).to have_css('[data-testid="flash"]', text: 'set by request_marker/a at 1')
    expect(marker.rendered).to have_css('[data-testid="variant"]', text: '[]')
    expect(marker.rendered).to have_css('[data-testid="header"]', text: 'nil')
    expect(marker.rendered).to have_css('[data-testid="cookie"]', text: 'nil')
  end

  it "starts every render with an empty flash, whatever the socket's session holds" do
    session = ActionController::TestSession.new('flash' => { 'discard' => [], 'flashes' => { 'notice' => 'Saved' } })
    connection = LiveCable::Connection.new(socket_request('rack.session' => session))

    expect(connection.view_context.flash[:notice]).to be_nil
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

  describe 'the page a component is on' do
    it "renders on a request for the page's path and query" do
      view = connection.view_context('/counter?q=shoes')

      expect(view.request.path).to eq('/counter')
      expect(view.request.original_fullpath).to eq('/counter?q=shoes')
      expect(view.params.to_unsafe_h).to include('q' => 'shoes', 'controller' => 'home', 'action' => 'counter')
      expect(view.current_page?('/counter')).to be(true)
      expect(view.url_for(page: 2)).to eq('/counter?page=2')
    end

    it "takes the path under the application's script name" do
      request = socket_request('SCRIPT_NAME' => '/shop', 'PATH_INFO' => '/cable', 'ORIGINAL_SCRIPT_NAME' => '/shop')
      view = LiveCable::Connection.new(request).view_context('/shop/counter')

      expect(view.request.path_info).to eq('/counter')
      expect(view.url_for(page: 2)).to eq('/shop/counter?page=2')
    end

    it 'renders a path no route matches without path parameters' do
      view = connection.view_context('/nowhere')

      expect(view.request.path).to eq('/nowhere')
      expect(view.request.path_parameters).to eq({})
    end

    it 'renders a page whose route constraint raises or throws without path parameters, once' do
      allow(ApplicationController._routes).to receive(:recognize_path_with_request).and_call_original

      %w[/authenticate /authenticated /authenticate /authenticated].each do |path|
        view = connection.view_context(path)

        expect(view.request.path).to eq(path)
        expect(view.request.path_parameters).to eq({})
      end
      expect(ApplicationController._routes).to have_received(:recognize_path_with_request).twice
    end

    it 'ignores what is not a path in the application' do
      request = socket_request('SCRIPT_NAME' => '/shop', 'ORIGINAL_SCRIPT_NAME' => '/shop')
      connection = LiveCable::Connection.new(request)

      ['//evil.test/counter', 'https://evil.test/counter', 'counter', '/shopping', '/counter'].each do |path|
        expect(connection.view_context(path).request.path).to eq('/shop')
      end
    end

    it 'recognizes each page once per connection' do
      allow(ApplicationController._routes).to receive(:recognize_path_with_request).and_call_original

      2.times { connection.view_context('/counter') }

      expect(ApplicationController._routes).to have_received(:recognize_path_with_request).once
    end

    it 'renders a component on the path it was mounted at' do
      component = live_mount('page_context', at: '/page_context?q=shoes')
      component.perform(:bump)

      expect(component.rendered).to have_css('[data-testid="current"]', text: 'true')
      expect(component.rendered).to have_css('[data-testid="next"][href="/page_context?page=2"]')
      expect(component.rendered).to have_css('[data-testid="query"]', text: 'shoes')
    end
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

      form = live_mount('page_context', connection:, at: '/page_context').rendered.find('form')
      token = form.find('input[name="authenticity_token"]', visible: :all).value

      post = socket_request('REQUEST_METHOD' => 'POST', 'PATH_INFO' => form[:action], 'rack.session' => session)
      post.request_parameters = { 'authenticity_token' => token }
      controller = ApplicationController.new.tap { |instance| instance.set_request!(post) }

      expect(controller.send(:verified_request?)).to be(true)
    end

    it 'renders forms with an authenticity token in the harness, as on a socket' do
      component = live_mount('page_context', at: '/page_context')

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
