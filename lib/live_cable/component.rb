# frozen_string_literal: true

module LiveCable
  class Component
    include ActiveSupport::Rescuable
    include ReactiveVariables
    include Identification
    include Lifecycle
    include Broadcasting
    include Rendering
    include Streaming
    include MethodDependencyTracking

    attr_accessor :live_connection

    # @return [String]
    attr_reader :id

    def initialize(id, **defaults)
      @id = id
      @rendered = false
      @subscribed = false
      @defaults = defaults
    end

    private

    # @return [Boolean]
    attr_reader :rendered

    # @return [Boolean]
    attr_reader :subscribed

    # @return [Hash]
    attr_reader :defaults

    # @return [LiveCable::Channel, nil]
    attr_reader :channel
  end
end
