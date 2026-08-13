# frozen_string_literal: true

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
