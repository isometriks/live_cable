# frozen_string_literal: true

require 'prism'

module LiveCable
  module Rendering
    # Turns the tokens of one top-level control block into Ruby that builds
    # the block's node (see Tree) instead of writing HTML, and collects the
    # statics of every scope inside it.
    #
    # The compiler tags the code token that opens or closes each branch and
    # loop body with a Structure, so the control flow itself is emitted as the
    # template wrote it and only the tagged points add bookkeeping:
    #
    #   <% if open %><p><%= title %></p><% else %><p>Closed</p><% end %>
    #
    #   __lc_1 = { "t" => nil }
    #   if open
    #   __lc_2 = []; __lc_1 = { "t" => 0, "d" => __lc_2 }
    #   __lc_2 << __lc_esc((title))
    #   else
    #   __lc_3 = []; __lc_1 = { "t" => 1, "d" => __lc_3 }
    #   end
    #   __lc_1
    #
    # Text goes into the statics of the scope it sits in and never reaches the
    # generated code. A construct the tree cannot split, such as a block
    # helper (`<%= form_with do %>`) or `content_for`, arrives between
    # :opaque_open and :opaque_close tokens and is captured to one HTML value.
    #
    # Raises Unsupported when the block uses control flow that would leave a
    # scope's values out of step with its statics (next, break, return, ...),
    # or when the tokens are not shaped as expected; the compiler then emits
    # the block as a plain HTML part, as it always has.
    class TreeBuilder
      class Unsupported < StandardError; end

      # @!attribute ops
      #   @return [Array<Array>] [:cond_open], [:branch, scope_id], [:cond_close],
      #     [:loop_open, scope_id, key_code], [:loop_close]
      Structure = Data.define(:ops)

      ESCAPING_CONTROL_FLOW = /(?<![.:\w])(?:next|break|redo|retry|return|throw)\b/
      CONDITIONAL_KEYWORD = /\A\s*(?:if|unless|case)\b/
      CODE_TYPES = %i[code expr expr_escaped expr_block expr_block_escaped expr_block_end].freeze
      EXPRESSION_TYPES = %i[expr expr_escaped].freeze

      Scope = Struct.new(:id, :var, :statics)
      Conditional = Struct.new(:var)
      Loop = Struct.new(:id, :rows, :keys)

      # @param tokens [Array<Array>] The block's tokens
      # @param raw_expression [Proc] (type) -> Boolean, whether an expression
      #   token is appended without escaping
      # @param opaque_code [Proc] (tokens) -> String, Ruby that writes the
      #   tokens to @output_buffer the way a plain part would
      def initialize(tokens, raw_expression:, opaque_code:)
        @tokens = tokens
        @raw_expression = raw_expression
        @opaque_code = opaque_code
        @stack = []
        @statics = {}
        @src = +''
        @result = nil
        @counter = 0
      end

      # @return [Array(String, Hash{Integer=>Array<String>})] The code and the statics
      def build
        index = 0

        while index < @tokens.length
          type, value, context = @tokens[index]

          case type
          when :text then add_text(value)
          when :code then add_code(value, context)
          when *EXPRESSION_TYPES then add_expression(type, value)
          when :opaque_open then index = add_opaque(index)
          else unsupported!("unexpected #{type} token")
          end

          index += 1
        end

        unsupported!('unbalanced block') unless @stack.empty? && @result

        @src << @result << "\n"

        [@src, @statics]
      end

      private

      def add_text(text)
        return if text.empty?

        # Ruby reads a CRLF in the source of a plain part as LF, so the
        # statics do the same.
        current_scope.statics.last << text.gsub("\r\n", "\n")
      end

      def add_code(code, structure)
        unless structure.is_a?(Structure)
          check_control_flow(code)
          emit(code)
          return
        end

        # `x = if ...` would take its value from the bookkeeping below
        if structure.ops.first.first == :cond_open && !code.match?(CONDITIONAL_KEYWORD)
          unsupported!('conditional used as a value')
        end

        structure.ops.each { |op, *args| before(op, *args) }
        emit(code)
        structure.ops.each { |op, *args| after(op, *args) }
      end

      def before(op, *args)
        case op
        when :cond_open
          var = next_var
          @src << "#{var} = { 't' => nil }\n"
          @stack << Conditional.new(var)
        when :branch
          close_scope if @stack.last.is_a?(Scope)
          unsupported!('branch outside a conditional') unless @stack.last.is_a?(Conditional)
        when :cond_close
          close_scope if @stack.last.is_a?(Scope)
        when :loop_open
          rows = next_var
          keys = args[1] ? next_var : nil
          @src << "#{rows} = []\n"
          @src << "#{keys} = []\n" if keys
          @stack << Loop.new(args[0], rows, keys)
        when :loop_close
          close_scope
        end
      end

      def after(op, *args)
        case op
        when :branch
          scope = open_scope(args[0])
          @src << "#{scope.var} = []; #{@stack[-2].var} = { 't' => #{scope.id}, 'd' => #{scope.var} }\n"
        when :cond_close
          conditional = @stack.pop
          unsupported!('end without a conditional') unless conditional.is_a?(Conditional)
          finish(conditional.var)
        when :loop_open
          loop_frame = @stack.last
          scope = open_scope(args[0])
          @src << "#{scope.var} = []; #{loop_frame.rows} << #{scope.var}\n"
          @src << "#{loop_frame.keys} << (#{args[1]}).to_s\n" if loop_frame.keys
        when :loop_close
          loop_frame = @stack.pop
          unsupported!('end without a loop') unless loop_frame.is_a?(Loop)

          node = next_var
          @src << "#{node} = { 't' => #{loop_frame.id}, 'r' => #{loop_frame.rows} }\n"

          if loop_frame.keys
            # Keys that repeat cannot tell rows apart, so such a loop is sent
            # as an unkeyed one and its rows are matched by position.
            @src << "#{node}['k'] = #{loop_frame.keys} if #{loop_frame.keys}.uniq.length == #{loop_frame.keys}.length\n"
          end

          finish(node)
        end
      end

      def add_expression(type, code)
        check_control_flow(code)
        method = @raw_expression.call(type) ? '__lc_raw' : '__lc_esc'
        add_value("#{method}((#{code}\n))")
      end

      def add_opaque(start)
        depth = 0
        index = start

        loop do
          index += 1
          unsupported!('unterminated opaque region') if index >= @tokens.length

          case @tokens[index][0]
          when :opaque_open then depth += 1
          when :opaque_close
            break if depth.zero?

            depth -= 1
          end
        end

        tokens = @tokens[(start + 1)...index].reject { |token| %i[opaque_open opaque_close].include?(token[0]) }
        tokens.each { |type, value| check_control_flow(value) if CODE_TYPES.include?(type) }

        code = @opaque_code.call(tokens)
        declare_locals(code)
        add_value("__lc_capture do\n#{code}\nend")

        index
      end

      # A variable the captured code assigns (`<% c = capture do %>`, a
      # begin/rescue that sets a total) is declared outside the capture block
      # first, so it outlives the block the way it would in a plain part.
      def declare_locals(code)
        result = Prism.parse(code)
        unsupported!('captured code does not parse') unless result.success?

        result.value.locals.each do |name|
          @src << "#{name} = nil if false\n" unless name.start_with?('__lc_')
        end
      end

      def check_control_flow(code)
        unsupported!('control flow leaves a scope early') if code.match?(ESCAPING_CONTROL_FLOW)
      end

      def add_value(code)
        scope = current_scope
        @src << "#{scope.var} << #{code}\n"
        scope.statics << +''
      end

      def finish(var)
        if @stack.empty?
          unsupported!('more than one block') if @result
          @result = var
        else
          add_value(var)
        end
      end

      def open_scope(id)
        scope = Scope.new(id, next_var, [+''])
        @statics[id] = scope.statics
        @stack << scope
        scope
      end

      def close_scope
        scope = @stack.pop
        unsupported!('scope closed out of order') unless scope.is_a?(Scope)
      end

      def current_scope
        scope = @stack.last
        unsupported!('content outside a branch or loop body') unless scope.is_a?(Scope)

        scope
      end

      def emit(code)
        @src << code << "\n"
      end

      def next_var
        @counter += 1
        "__lc_#{@counter}"
      end

      def unsupported!(reason)
        raise Unsupported, reason
      end
    end
  end
end
