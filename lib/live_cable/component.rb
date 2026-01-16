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

    attr_accessor :live_connection

    def initialize(id, **defaults)
      @id = id
      @rendered = false
      @subscribed = false
      @defaults = defaults
    end

    private

    # @return [LiveCable::Channel, nil]
    attr_reader :channel
  end
end
