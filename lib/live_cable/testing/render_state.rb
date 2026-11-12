# frozen_string_literal: true

module LiveCable
  module Testing
    # Reconstructs a component's rendered HTML from _refresh broadcasts,
    # mirroring what the JavaScript client does: the first refresh carries
    # all parts, subsequent refreshes carry only the changed parts (nil
    # means unchanged), and child components arrive as separate results
    # referenced by <LiveCable child-live-id="..."> placeholders. Results for
    # children at every depth arrive in the root's c, so the whole tree
    # shares one set of child states.
    #
    # A control block's part is a node or a diff against the node already
    # held (see LiveCable::Rendering::Tree), rendered with the statics that
    # arrive in s.
    class RenderState
      CHILD_PLACEHOLDER = %r{<LiveCable child-live-id="(?<live_id>[^"]+)"></LiveCable>}

      def initialize(children = Hash.new { |hash, key| hash[key] = RenderState.new(hash) })
        @parts_by_template = {}
        @statics_by_template = Hash.new { |hash, key| hash[key] = {} }
        @last_template = nil
        @children = children
      end

      # @param refresh [Hash] A _refresh payload ({ h:, p:, c: })
      def apply(refresh)
        refresh = refresh.as_json # Normalize symbol/string keys

        template = refresh['h'] || @last_template || 'default'
        @last_template = template

        parts = refresh['p'] || []
        @statics_by_template[template].merge!(refresh['s'] || {})

        if @parts_by_template.key?(template)
          stored = @parts_by_template[template]

          parts.each_with_index do |part, index|
            stored[index] = Rendering::Tree.apply(stored[index], part) unless part.nil?
          end
        else
          @parts_by_template[template] = parts.dup
        end

        (refresh['c'] || {}).each do |live_id, child_refresh|
          @children[live_id].apply(child_refresh)
        end
      end

      # @param template_hash [String] The h of the template's renders
      # @param stream [LiveCable::Rendering::Streams::Stream]
      # @return [Array<String>] The keys of the stream's rows, in order, or
      #   none when it isn't shown
      def stream_keys(template_hash, stream)
        node = Rendering::Tree.node_at(@parts_by_template[template_hash]&.[](stream.part), stream.path)
        node.is_a?(Hash) && node['st'] == stream.name.to_s ? node['k'] : []
      end

      # @return [String] The reconstructed HTML with child placeholders resolved
      def html
        parts = @parts_by_template[@last_template]
        return '' unless parts

        statics = @statics_by_template[@last_template]

        parts.map { |part| Rendering::Tree.render(part, statics) }.join.gsub(CHILD_PLACEHOLDER) do
          @children[CGI.unescapeHTML(Regexp.last_match[:live_id])].html
        end
      end
    end
  end
end
