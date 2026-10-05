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

    # Carried children stay out of #children, which broadcast_changeset reads as
    # "rendered this cycle": a child there gets no render of its own that cycle.
    #
    # @param previous [RenderContext]
    def inherit_skipped(previous)
      @children_by_part.reverse_merge!(previous.children_by_part)
    end

    # @return [Array<LiveCable::Component>]
    def owned_children
      children_by_part.values.flatten.uniq
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
      locations = (tracked_values[value] ||= [])

      # `todos.first` builds a new wrapper on every call; one per set of observers is enough
      unless locations.any? { |root, _path| root.same_live_cable_observers?(delegator) }
        locations << [delegator, []]
        unindexed << delegator
      end

      value
    end

    # @param value [Array, Hash] a plain collection a component method returned
    # @return [Array, Hash] the collection with no Delegator left in it
    def unwrap_nested(value)
      unwrapped_nested[value] ||= Delegator.unwrap(value) { |delegator| unwrap(delegator) }
    end

    # Maps a prop back to tracked values, so a child's changes still mark this
    # component's variables, even through a collection built in the template.
    def track(value)
      return value unless Delegator.supported?(value)

      # A child given a variable's own value shares its wrapper, so changes on either side re-render both
      stored = stored_wrappers[value]
      return stored if stored

      while (delegator = unindexed.shift)
        index_nested(delegator, delegator.__getobj__, [])
      end

      locations = tracked_values[value]
      if locations&.one?
        delegator, path = locations.first
        return path.reduce(delegator) { |nested, key| nested[key] }
      end

      sources = locations ? locations.map(&:first) : sources_within(value).keys
      return value if sources.empty?

      Delegator.new(value).tap do |wrapped|
        sources.each { |source| source.share_live_cable_observers_with(wrapped) }
      end
    end

    # A finished context is kept until the next render; drop what it unwrapped.
    def forget_tracked_values
      @tracked_values = @unindexed = @unwrapped_nested = @stored_wrappers = nil
    end

    private

    # @return [LiveCable::RenderContext, nil]
    attr_reader :root

    # @return [Hash{Object => Array<Array(LiveCable::Delegator, Array)>}] by identity
    def tracked_values
      @tracked_values ||= {}.compare_by_identity
    end

    # @return [Array<LiveCable::Delegator>]
    def unindexed
      @unindexed ||= []
    end

    # @return [Hash{Object => LiveCable::Delegator}] by identity, each variable's value to the wrapper storing it
    def stored_wrappers
      @stored_wrappers ||= begin
        variables = component.all_reactive_variables | component.shared_variables

        variables.each_with_object({}.compare_by_identity) do |variable, wrappers|
          value = component.public_send(variable)
          wrappers[value.__getobj__] ||= value if value.is_a?(Delegator)
        end
      end
    end

    # @return [Hash{Object => Object}] by identity
    def unwrapped_nested
      @unwrapped_nested ||= {}.compare_by_identity
    end

    def index_nested(delegator, value, path, seen = {}.compare_by_identity)
      nested_entries(value).each do |key, child|
        next if !Delegator.supported?(child) || seen.key?(child)

        seen[child] = true
        (tracked_values[child] ||= []) << [delegator, path + [key]]
        index_nested(delegator, child, path + [key], seen)
      end
    end

    # @return [Hash{LiveCable::Delegator => true}] by identity
    def sources_within(value, sources = {}.compare_by_identity, seen = {}.compare_by_identity)
      nested_entries(value).map(&:last).each do |child|
        next if !Delegator.supported?(child) || seen.key?(child)

        seen[child] = true
        locations = tracked_values[child]

        if locations
          locations.each { |location| sources[location.first] = true }
        else
          sources_within(child, sources, seen)
        end
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
