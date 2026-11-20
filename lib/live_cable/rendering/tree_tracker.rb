# frozen_string_literal: true

module LiveCable
  module Rendering
    # Remembers, per template, the tree nodes a component's client holds and
    # the statics it has been sent, so each render sends only what changed.
    #
    # A component lives as long as its connection, and its client keeps what
    # it was sent for as long as the component is on the page, so the two stay
    # in step the same way the static parts already do (see static_sent in
    # Component::Rendering).
    class TreeTracker
      State = Struct.new(:nodes, :sent_scopes, :statics)

      def initialize
        @states = {}
      end

      # Forgets what the client holds for a template, before a full render.
      #
      # @param template [String]
      def reset(template)
        @states.delete(template)
      end

      # Replaces each tree node in the rendered parts with its diff against
      # the node last sent at that position, and collects the statics the
      # client has not seen.
      #
      # A collection stream's node is kept as its placeholder, so no rows are.
      #
      # @param template [String] The template the parts were rendered from
      # @param parts [Array<String, Hash, nil>] Rendered parts; nil is unchanged
      # @param statics [Hash{Integer=>Array<String>}] The template's statics
      # @param streams [Enumerable<Streams::Stream>] The template's streams
      # @return [Array(Array, Hash)] The parts to send and the statics to send with them
      def process(template, parts, statics, streams = [])
        state = @states[template]

        # A recompiled template (edited in development) numbers its scopes
        # afresh, so what the client holds for the old one no longer applies.
        state = nil if state && state.statics != statics
        state ||= (@states[template] = State.new({}, Set.new, statics))
        needed = {}

        sent = parts.each_with_index.map do |part, index|
          unless part.is_a?(Hash)
            state.nodes.delete(index) unless part.nil?
            next part
          end

          collect_statics(state, Tree.scope_ids(part), needed)

          previous = state.nodes[index]
          state.nodes[index] = streams.reduce(part) do |node, stream|
            stream.part == index ? Tree.without_stream_rows(node, stream.path, placeholder(stream)) : node
          end

          previous ? Tree.diff(previous, part) : part
        end

        [sent, needed]
      end

      # @param stream [Streams::Stream]
      # @return [Boolean] whether the client holds the stream where the
      #   template puts it
      def held_stream?(template, statics, stream)
        state = known(template, statics)
        !state.nil? && Tree.node_at(state.nodes[stream.part], stream.path) == placeholder(stream)
      end

      # @return [Boolean] whether the client holds anything for the template
      def known?(template, statics)
        !known(template, statics).nil?
      end

      # @param update [Hash] A stream's node, or its {"o" => ops} diff
      # @return [Hash{Integer=>Array<String>}] The statics of scopes the
      #   update uses that the client hasn't seen
      def statics_for(template, update)
        state = @states.fetch(template)
        values = update.key?('o') ? update['o'].filter_map { |op| op[2] if op[0] != 'd' }.flatten(1) : [update]

        collect_statics(state, values.flat_map { |value| Tree.scope_ids(value) }, {})
      end

      private

      def known(template, statics)
        state = @states[template]
        state if state&.statics == statics
      end

      def placeholder(stream)
        Tree::StreamPlaceholder.for(stream.name, stream.scope)
      end

      def collect_statics(state, scopes, needed)
        scopes.each do |scope|
          next if state.sent_scopes.include?(scope)

          needed[scope] = state.statics.fetch(scope)
          state.sent_scopes << scope
        end

        needed
      end
    end
  end
end
