# frozen_string_literal: true

module LiveCable
  class Connection
    extend ActiveSupport::Autoload

    autoload :ComponentManagement
    autoload :ChannelManagement
    autoload :StateManagement
    autoload :Messaging
    autoload :Broadcasting
    autoload :ErrorHandling

    include ComponentManagement
    include ChannelManagement
    include StateManagement
    include Messaging
    include Broadcasting
    include ErrorHandling

    SHARED_CONTAINER = '_shared'

    def initialize(request)
      @request = request
      @session_id = SecureRandom.uuid
      @containers = Hash.new { |hash, key| hash[key] = Container.new }
      @components = {}
      @channels = {}
    end

    private

    # @return [String]
    attr_reader :session_id

    # @return [ActionDispatch::Request]
    attr_reader :request

    # @return [Hash<String, Container>]
    attr_reader :containers

    # @return [Hash<String, Component>]
    attr_reader :components
  end
end
