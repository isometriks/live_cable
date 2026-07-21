# frozen_string_literal: true

module LiveCable
  module Testing
    # Reconstructs a component's rendered HTML from _refresh broadcasts,
    # mirroring what the JavaScript client does: the first refresh carries
    # all parts, subsequent refreshes carry only the changed parts (nil
    # means unchanged), and child components arrive as separate results
    # referenced by <LiveCable child-live-id="..."> placeholders.
    class RenderState
      CHILD_PLACEHOLDER = %r{<LiveCable child-live-id="(?<live_id>[^"]+)"></LiveCable>}

      def initialize
        @parts_by_template = {}
        @last_template = nil
        @children = Hash.new { |hash, key| hash[key] = RenderState.new }
      end

      # @param refresh [Hash] A _refresh payload ({ h:, p:, c: })
      def apply(refresh)
        refresh = refresh.as_json # Normalize symbol/string keys

        template = refresh['h'] || @last_template || 'default'
        @last_template = template

        parts = refresh['p'] || []

        if @parts_by_template.key?(template)
          parts.each_with_index do |part, index|
            @parts_by_template[template][index] = part unless part.nil?
          end
        else
          @parts_by_template[template] = parts.dup
        end

        (refresh['c'] || {}).each do |live_id, child_refresh|
          @children[live_id].apply(child_refresh)
        end
      end

      # @return [String] The reconstructed HTML with child placeholders resolved
      def html
        parts = @parts_by_template[@last_template]
        return '' unless parts

        parts.join.gsub(CHILD_PLACEHOLDER) do
          @children[Regexp.last_match[:live_id]].html
        end
      end
    end
  end
end
