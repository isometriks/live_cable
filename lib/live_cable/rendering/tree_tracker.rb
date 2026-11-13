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
      # @param template [String] The template the parts were rendered from
      # @param parts [Array<String, Hash, nil>] Rendered parts; nil is unchanged
      # @param statics [Hash{Integer=>Array<String>}] The template's statics
      # @return [Array(Array, Hash)] The parts to send and the statics to send with them
      def process(template, parts, statics)
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

          Tree.scope_ids(part).each do |scope|
            needed[scope] = statics.fetch(scope) unless state.sent_scopes.include?(scope)
          end

          previous = state.nodes[index]
          state.nodes[index] = part

          previous ? Tree.diff(previous, part) : part
        end

        state.sent_scopes.merge(needed.keys)

        [sent, needed]
      end
    end
  end
end
