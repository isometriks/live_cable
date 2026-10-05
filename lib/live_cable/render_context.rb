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

    # @param delegator [LiveCable::Delegator]
    # @return [Object] the value the template sees
    def unwrap(delegator)
      value = delegator.__getobj__

      unless tracked_values.key?(value)
        tracked_values[value] = [delegator, []]
        unindexed << delegator
      end

      value
    end

    # Maps a prop back to tracked values, so a child's changes still mark this
    # component's variables, even through a collection built in the template.
    def track(value)
      return value unless Delegator.supported?(value)

      while (delegator = unindexed.shift)
        index_nested(delegator, delegator.__getobj__, [])
      end

      delegator, path = tracked_values[value]
      return path.reduce(delegator) { |nested, key| nested[key] } if delegator

      sources = sources_within(value)
      return value if sources.empty?

      Delegator.new(value).tap do |wrapped|
        sources.each_key { |source| source.share_live_cable_observers_with(wrapped) }
      end
    end

    private

    # @return [LiveCable::RenderContext, nil]
    attr_reader :root

    # @return [Hash{Object => Array(LiveCable::Delegator, Array)}] by identity
    def tracked_values
      @tracked_values ||= {}.compare_by_identity
    end

    # @return [Array<LiveCable::Delegator>]
    def unindexed
      @unindexed ||= []
    end

    def index_nested(delegator, value, path)
      nested_entries(value).each do |key, child|
        next if !Delegator.supported?(child) || tracked_values.key?(child)

        tracked_values[child] = [delegator, path + [key]]
        index_nested(delegator, child, path + [key])
      end
    end

    # @return [Hash{LiveCable::Delegator => true}] by identity
    def sources_within(value, sources = {}.compare_by_identity, seen = {}.compare_by_identity)
      nested_entries(value).map(&:last).each do |child|
        next if !Delegator.supported?(child) || seen.key?(child)

        seen[child] = true
        delegator, = tracked_values[child]
        delegator ? sources[delegator] = true : sources_within(child, sources, seen)
      end

      sources
    end

    def nested_entries(value)
      case value
      when Hash then value.each_pair
      when Array then value.each_with_index.map { |child, index| [index, child] }
      else []
      end
    end
  end
end
