# frozen_string_literal: true

require 'monitor'

module LiveCable
  class Connection
    include ComponentManagement
    include StateManagement
    include Messaging
    include Broadcasting
    include ErrorHandling

    SHARED_CONTAINER = '_shared'

    def initialize(request)
      @request = request
      @containers = Hash.new { |hash, key| hash[key] = Container.new }
      @components = {}
      # A single Connection instance is shared by every component subscription
      # on one ActionCable connection, and ActionCable dispatches that
      # connection's incoming commands (and stream-broadcast callbacks) on a
      # shared worker-thread pool with no per-connection serialization. Guard
      # the shared @components/@containers mutations so concurrent messages
      # can't corrupt them. A Monitor is re-entrant, so the nested calls
      # (receive -> broadcast_changeset -> set) don't deadlock.
      @monitor = Monitor.new
    end

    # Run a block holding this connection's lock. Callers that perform a
    # multi-step mutation across the shared state (subscribe, unsubscribe, a
    # stream callback) should wrap the whole sequence so it's atomic.
    def synchronize(&)
      @monitor.synchronize(&)
    end

    # A view context reused across every render on this connection. Building
    # one controller/request/view context per render (as ActionController's
    # renderer does) is a large share of render time, and none of that
    # per-request state is meaningful on a WebSocket render. Renders are
    # serialized by the connection lock, so a single shared context is safe.
    def view_context
      @view_context ||= build_view_context
    end

    private

    def build_view_context
      request = ActionDispatch::Request.new(ActionController::Renderer::DEFAULT_ENV.dup)
      request.routes = ApplicationController._routes

      controller = ApplicationController.new
      controller.set_request!(request)
      controller.set_response!(ApplicationController.make_response!(request))
      controller.view_context
    end

    # @return [ActionDispatch::Request]
    attr_reader :request

    # @return [Hash<String, Container>]
    attr_reader :containers

    # @return [Hash<String, Component>]
    attr_reader :components
  end
end
