# frozen_string_literal: true

module LiveCable
  class RenderContext
    def initialize(component, root: false)
      @component = component
      @children = []
      @root = root
    end

    # @return [Array<LiveCable::Component>]
    attr_reader :children

    # @return [LiveCable::Component]
    attr_reader :component

    def root?
      @root
    end

    def reset
      self.children = []
    end

    def clear
      @children = nil
      @component = nil
    end

    def add_component(child)
      return unless live_connection

      live_connection.add_component(child)
      children << child
    end

    # @return [LiveCable::Component, nil]
    def get_component(live_id)
      live_connection&.get_component(live_id)
    end

    # @return [LiveCable::Connection]
    def live_connection
      component.live_connection
    end
  end
end
