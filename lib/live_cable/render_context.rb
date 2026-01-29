# frozen_string_literal: true

module LiveCable
  class RenderContext
    def initialize(component, root: nil)
      @component = component
      @children = []
      @root = root
      @render_results = {}
    end

    # @return [Array<LiveCable::Component>]
    attr_reader :children

    # @return [LiveCable::Component]
    attr_reader :component

    # @return [Hash<String, RenderResult>]
    attr_reader :render_results

    def root?
      root.nil?
    end

    def reset
      self.children = []
    end

    def clear
      @children = nil
      @component = nil
    end

    # @param result [RenderResult]
    def <<(result)
      if root?
        render_results[result.live_id] = result
      else
        root << result
      end
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

    private

    # @return [LiveCable::RenderContext, nil]
    attr_reader :root
  end
end
