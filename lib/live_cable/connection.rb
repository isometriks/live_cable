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
      @monitor = Monitor.new
    end

    # Run a block holding this connection's lock.
    #
    # One Connection is shared by every component on a socket, but ActionCable
    # runs a socket's work - each incoming message, each subscribe and
    # unsubscribe, each stream_from callback - as separate jobs on a worker
    # pool shared by the whole server, with nothing keeping two jobs for the
    # same socket apart. Every such entry point holds this lock for its whole
    # duration, action and render included, so a stream callback can't land
    # between an action's write and the push that follows it.
    #
    # A Monitor rather than a Mutex because the calls nest: receive ->
    # broadcast_changeset -> add_component all take it again on one thread.
    # Only ever one connection's lock per job - never take another
    # connection's while holding this one.
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
