# frozen_string_literal: true

module LiveCable
  class RenderContext
    def initialize(component, root: nil)
      @component = component
      @children = []
      @root = root
      @render_results = {}
      @children_by_part = {}
      @current_part = nil
    end

    # @return [Array<LiveCable::Component>]
    attr_reader :children

    # @return [LiveCable::Component]
    attr_reader :component

    # @return [Hash<String, RenderResult>]
    attr_reader :render_results

    # @return [Hash<Integer, Array<LiveCable::Component>>]
    attr_reader :children_by_part

    def render_part(index)
      @current_part = index
      result = yield
      @children_by_part[index] ||= [] unless result.nil?
      result
    end

    # Returns children from the previous context that came from parts which were
    # skipped (not rendered) in this render cycle. These children should not be
    # destroyed — their part simply didn't re-evaluate.
    #
    # @param previous_context [RenderContext]
    # @return [Array<LiveCable::Component>]
    def preserved_children_from(previous_context)
      previous_context.children_by_part.each_with_object([]) do |(part, part_children), preserved|
        preserved.concat(part_children) unless @children_by_part.key?(part)
      end
    end

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
      (@children_by_part[@current_part] ||= []) << child
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
