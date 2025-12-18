# frozen_string_literal: true

module LiveCable
  class RenderContext
    def initialize(component)
      @component = component
      @children = []
    end

    # @return [Array<LiveCable::Component>]
    attr_reader :children

    def reset
      self.children = []
    end

    def add_component(child)
      return unless component.live_connection

      component.live_connection.add_component(child)
      children << child
    end

    # @return [LiveCable::Component, nil]
    def get_component(live_id)
      component.live_connection&.get_component(live_id)
    end

    # @return [LiveCable::Connection]
    def live_connection
      component.live_connection
    end

    private

    # @return [LiveCable::Component]
    attr_reader :component
  end
end
