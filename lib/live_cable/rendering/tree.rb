# frozen_string_literal: true

module LiveCable
  module Rendering
    # The wire format for the structured parts a .live.erb template compiles
    # control blocks into, and the operations on it.
    #
    # A control block at the top of a template (an if, unless, case, a loop)
    # renders to a node instead of an HTML string. The markup the block writes
    # is split at compile time into static strings, grouped by scope - one
    # scope per branch and one per loop body - and the node carries only the
    # values that fill the gaps between them:
    #
    #   <% if open %><p><%= title %></p><% else %><p>Closed</p><% end %>
    #
    #   statics: { 0 => ["<p>", "</p>"], 1 => ["<p>Closed</p>"] }
    #   node:    { "t" => 0, "d" => ["Hello"] }   # when open
    #            { "t" => 1, "d" => [] }          # otherwise
    #            { "t" => nil }                   # an if with no branch taken
    #
    # A loop holds one list of values per row, under the scope of its body,
    # and the row keys when the body declares them (live-key or id):
    #
    #   <% todos.each do |todo| %><li id="todo-<%= todo.id %>"><%= todo.title %></li><% end %>
    #
    #   statics: { 2 => ['<li id="todo-', '">', "</li>"] }
    #   node:    { "t" => 2, "r" => [["1", "Milk"], ["2", "Eggs"]], "k" => ["todo-1", "todo-2"] }
    #
    # A value is either an HTML string or a nested node, so branches and loops
    # nest as deeply as the template does.
    #
    # Statics are sent to a client once per template, and after the first
    # render a part carries a diff against the node the client already holds
    # rather than the whole node (see .diff). A node always has a "t" key and a
    # diff never does, which is how .apply tells them apart.
    module Tree
      module_function

      # @param node [Hash, String, nil] A node or an HTML string
      # @param statics [Hash{Integer=>Array<String>}] Statics by scope id
      # @return [String] The HTML the node stands for
      def render(node, statics)
        return node.to_s unless node.is_a?(Hash)

        scope = scope_of(node)
        return '' if scope.nil?

        template = statics.fetch(scope) { statics.fetch(scope.to_s) }

        if loop?(node)
          node['r'].sum('') { |row| interleave(template, row, statics) }
        else
          interleave(template, node['d'], statics)
        end
      end

      # The update that turns prev into current, or nil when they are equal.
      #
      # @param prev [Hash] The node the client holds
      # @param current [Hash] The node just rendered
      # @return [Hash, nil]
      def diff(prev, current)
        return current unless prev.is_a?(Hash) && current.is_a?(Hash)
        return current if scope_of(prev) != scope_of(current) || loop?(prev) != loop?(current)
        return nil if scope_of(current).nil?

        loop?(current) ? diff_loop(prev, current) : wrap('d', diff_values(prev['d'], current['d']))
      end

      # Applies an update to a node, as the client does. An update with a "t"
      # key is a whole node and replaces what was there.
      #
      # @param stored [Hash, String, nil] What the client holds
      # @param update [Hash, String] A node, a diff or an HTML string
      # @return [Hash, String] The new node
      def apply(stored, update)
        return update unless update.is_a?(Hash) && !update.key?('t') && stored.is_a?(Hash)

        if loop?(stored)
          apply_loop(stored, update)
        else
          stored.merge('d' => apply_values(stored['d'], update['d']))
        end
      end

      # @param node [Hash, String, nil]
      # @return [Array<Integer>] The scope ids the node and its children use
      def scope_ids(node, ids = [])
        return ids unless node.is_a?(Hash)

        scope = scope_of(node)
        return ids if scope.nil?

        ids << scope
        rows = loop?(node) ? node['r'] : [node['d']]
        rows.each { |row| row.each { |value| scope_ids(value, ids) } }
        ids
      end

      def scope_of(node)
        node['t']
      end

      def loop?(node)
        node.key?('r')
      end

      def interleave(template, values, statics)
        html = +template[0].to_s

        values.each_with_index do |value, index|
          html << render(value, statics) << template[index + 1].to_s
        end

        html
      end

      def wrap(key, value)
        value.nil? ? nil : { key => value }
      end

      # Values at the same index of the same scope, so the lists are always
      # the same length. Unchanged values are left out.
      def diff_values(prev, current)
        changes = {}

        current.each_with_index do |value, index|
          change = diff_value(prev[index], value)
          changes[index.to_s] = change unless change.nil?
        end

        changes.empty? ? nil : changes
      end

      def diff_value(prev, value)
        if value.is_a?(Hash)
          prev.is_a?(Hash) ? diff(prev, value) : value
        else
          prev == value ? nil : value
        end
      end

      # Rows are matched by key, or by position when the loop has no keys.
      # The new order is sent only when it changed: the keys for a keyed loop,
      # the row count for an unkeyed one. A row the client has not seen comes
      # whole; a row it has comes as a diff of its values.
      def diff_loop(prev, current)
        return current if prev.key?('k') != current.key?('k')

        prev_keys = row_keys(prev)
        current_keys = row_keys(current)
        prev_rows = prev_keys.zip(prev['r']).to_h

        update = {}

        if current.key?('k')
          update['k'] = current_keys if prev_keys != current_keys
        elsif prev_keys.length != current_keys.length
          update['n'] = current_keys.length
        end

        rows = {}

        current_keys.each_with_index do |key, index|
          row = current['r'][index]

          if prev_rows.key?(key)
            change = diff_values(prev_rows[key], row)
            rows[key] = change unless change.nil?
          else
            rows[key] = row
          end
        end

        update['r'] = rows unless rows.empty?
        update.empty? ? nil : update
      end

      def apply_loop(stored, update)
        stored_keys = row_keys(stored)
        stored_rows = stored_keys.zip(stored['r']).to_h

        keys = if update.key?('k')
                 update['k']
               elsif update.key?('n')
                 Array.new(update['n'], &:to_s)
               else
                 stored_keys
               end

        changes = update['r'] || {}

        rows = keys.map do |key|
          change = changes[key]

          if change.is_a?(Array)
            change
          elsif change
            apply_values(stored_rows.fetch(key), change)
          else
            stored_rows.fetch(key)
          end
        end

        node = stored.merge('r' => rows)
        node['k'] = keys if stored.key?('k')
        node
      end

      def apply_values(values, changes)
        return values if changes.nil?

        values = values.dup

        changes.each do |index, change|
          index = index.to_i
          values[index] = apply(values[index], change)
        end

        values
      end

      def row_keys(node)
        node['k'] || Array.new(node['r'].length, &:to_s)
      end
    end
  end
end
