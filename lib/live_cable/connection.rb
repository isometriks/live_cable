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

    private

    # @return [ActionDispatch::Request]
    attr_reader :request

    # @return [Hash<String, Container>]
    attr_reader :containers

    # @return [Hash<String, Component>]
    attr_reader :components
  end
end
