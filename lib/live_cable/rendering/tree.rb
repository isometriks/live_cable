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
    #
    # A keyed loop's diff is a list of row ops, applied in order:
    #
    #   { "o" => [["d", "todo-3", "todo-7"],             # delete these rows
    #             ["a", "todo-9", row],                  # append
    #             ["p", "todo-8", row],                  # prepend
    #             ["i", "todo-6", row, "todo-2"],        # insert after todo-2
    #             ["m", "todo-1", "todo-6"],             # move after todo-6 (nil: to the front)
    #             ["s", "todo-6", "todo-1", "todo-2"],   # sort: these rows first, in this order
    #             ["u", "todo-2", { "1" => "Eggs" }],    # update: changed values, or a whole row
    #             ["r"]] }                               # reset: drop every row
    #
    # An insert of a key already held replaces that row and moves it, and a
    # delete or sort of a key not held skips it, so a sender that doesn't
    # remember the rows (a stream) can use the same ops. Rows a sort doesn't
    # name follow the ones it does, in their order.
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

        # With "ik", each row leaves out the id the compiler gave it, which is its key
        if loop?(node) && node['ik']
          keys = node['k']
          node['r'].each_with_index.with_object(+'') do |(row, index), html|
            html << interleave(template, row, statics, CGI.escapeHTML(keys[index]))
          end
        elsif loop?(node)
          node['r'].map { |row| interleave(template, row, statics) }.join
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

      # A key fills the first gap, ahead of the values
      def interleave(template, values, statics, key = nil)
        html = String.new(template[0].to_s)
        offset = key ? 1 : 0
        html << key << template[1].to_s if key

        values.each_with_index do |value, index|
          html << render(value, statics) << template[index + offset + 1].to_s
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

      def diff_loop(prev, current)
        return current if prev.key?('k') != current.key?('k')

        current.key?('k') ? diff_keyed_loop(prev, current) : diff_unkeyed_loop(prev, current)
      end

      # Rows are matched by position. The row count is sent when it changed;
      # a row the client has not seen comes whole, one it has as a diff.
      def diff_unkeyed_loop(prev, current)
        update = {}
        update['n'] = current['r'].length if prev['r'].length != current['r'].length

        rows = {}

        current['r'].each_with_index do |row, index|
          if index < prev['r'].length
            change = diff_values(prev['r'][index], row)
            rows[index.to_s] = change unless change.nil?
          else
            rows[index.to_s] = row
          end
        end

        update['r'] = rows unless rows.empty?
        update.empty? ? nil : update
      end

      # Row ops that turn prev's rows into current's: one delete for the rows
      # that went, then, in the new order, an insert for each new row, a move
      # for each kept row outside the longest run already in order, and an
      # update for each kept row whose values changed. When the moves would
      # be bigger than the kept rows' new order, that order is sent as one
      # sort instead. When no row is kept the whole node is smaller, and
      # leaves the client nothing to anchor to.
      def diff_keyed_loop(prev, current)
        return diff_keyed_rows(prev, current) if prev['k'] == current['k']

        prev_rows = prev['k'].zip(prev['r']).to_h
        current_keys = current['k']
        current_index = current_keys.each_with_index.to_h
        kept = prev['k'].select { |key| current_index.key?(key) }

        return current if kept.empty?

        removed = prev['k'].reject { |key| current_index.key?(key) }
        positions = kept.map { |key| current_index[key] }
        in_order = increasing_run(positions).to_set { |index| current_keys[index] }
        last_kept = positions.max
        ops = []
        moves = []
        after = nil

        current_keys.each_with_index do |key, index|
          row = current['r'][index]

          if prev_rows.key?(key)
            unless in_order.include?(key)
              moves << ['m', key, after]
              ops << moves.last
            end

            change = diff_values(prev_rows[key], row)
            ops << ['u', key, change] unless change.nil?
          else
            ops << insert_op(key, row, after, appended: index > last_kept)
          end

          after = key
        end

        ops = sort_instead_of(moves, ops, positions.sort.map { |index| current_keys[index] })
        ops.unshift(['d', *removed]) unless removed.empty?
        ops.empty? ? nil : { 'o' => ops }
      end

      def diff_keyed_rows(prev, current)
        ops = []

        current['k'].each_with_index do |key, index|
          change = diff_values(prev['r'][index], current['r'][index])
          ops << ['u', key, change] unless change.nil?
        end

        ops.empty? ? nil : { 'o' => ops }
      end

      def sort_instead_of(moves, ops, order)
        return ops if moves.empty?

        sort = ['s', *order]
        return ops if JSON.generate(sort).bytesize >= JSON.generate(moves).bytesize

        [sort, *ops.reject { |op| op[0] == 'm' }]
      end

      def insert_op(key, row, after, appended:)
        if after.nil?
          ['p', key, row]
        elsif appended
          ['a', key, row]
        else
          ['i', key, row, after]
        end
      end

      # The values of a longest strictly increasing subsequence of positions.
      def increasing_run(positions)
        tails = []
        previous = Array.new(positions.length)

        positions.each_with_index do |position, index|
          slot = tails.bsearch_index { |tail| positions[tail] >= position } || tails.length
          previous[index] = tails[slot - 1] if slot.positive?
          tails[slot] = index
        end

        run = []
        index = tails.last

        until index.nil?
          run.unshift(positions[index])
          index = previous[index]
        end

        run
      end

      def apply_loop(stored, update)
        return apply_ops(stored, update['o'] || []) if stored.key?('k')

        changes = update['r'] || {}
        count = update.fetch('n', stored['r'].length)

        rows = Array.new(count) do |index|
          change = changes[index.to_s]

          if change.is_a?(Array)
            change
          elsif change
            apply_values(stored['r'].fetch(index), change)
          else
            stored['r'].fetch(index)
          end
        end

        stored.merge('r' => rows)
      end

      def apply_ops(stored, ops)
        keys = stored['k'].dup
        rows = keys.zip(stored['r']).to_h

        ops.each do |code, key, *args|
          case code
          when 'd'
            [key, *args].each { |gone| keys.delete(gone) if rows.delete(gone) }
          when 'a', 'p', 'i'
            keys.delete(key) if rows.key?(key)
            rows[key] = args[0]
            keys.insert(insert_position(code, keys, args[1]), key)
          when 'm'
            rows.fetch(key)
            keys.delete(key)
            keys.insert(args[0].nil? ? 0 : key_index(keys, args[0]) + 1, key)
          when 'u'
            rows[key] = args[0].is_a?(Array) ? args[0] : apply_values(rows.fetch(key), args[0])
          when 's'
            named = [key, *args].uniq.select { |held| rows.key?(held) }
            keys = named + (keys - named)
          when 'r'
            keys.clear
            rows.clear
          end
        end

        stored.merge('r' => keys.map { |key| rows[key] }, 'k' => keys)
      end

      def insert_position(code, keys, after)
        case code
        when 'a' then keys.length
        when 'p' then 0
        else key_index(keys, after) + 1
        end
      end

      def key_index(keys, key)
        keys.index(key) || raise(KeyError, "no row #{key}")
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
    end
  end
end
