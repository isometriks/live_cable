# frozen_string_literal: true

module LiveCable
  class Component
    extend ActiveSupport::Autoload

    autoload :ReactiveVariables
    autoload :Identification
    autoload :Lifecycle
    autoload :Broadcasting
    autoload :Rendering
    autoload :Streaming

    include ActiveSupport::Rescuable
    include ReactiveVariables
    include Identification
    include Lifecycle
    include Broadcasting
    include Rendering
    include Streaming

    attr_accessor :live_connection, :channel

    def initialize(id)
      @id = id
      @rendered = false
      @subscribed = false
    end
  end
end
