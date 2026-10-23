# frozen_string_literal: true

require 'prism'

module LiveCable
  module Rendering
    # Splits a .live.erb template into parts: one per top-level text, Ruby tag
    # or control block. A control block that branches or loops compiles to a
    # node (see Tree and TreeBuilder), so a change inside it sends only the
    # values that changed; any other block renders to one HTML string.
    #
    # The structure is recorded by tagging tokens rather than by emitting new
    # ones, so the whitespace Herb produces is the same either way.
    class Compiler < ::Herb::Engine::Compiler
      Structure = TreeBuilder::Structure

      # Block helpers whose body runs once per element, so the body can be
      # split into a row of values like a for or while loop. Any other block
      # (content_for, cache, capture, a form builder...) may capture or discard
      # what its body writes, so it is rendered to HTML as one value instead.
      ITERATION_METHODS = %i[
        each each_with_index each_with_object each_slice each_cons each_pair each_key each_value each_entry
        reverse_each find_each times upto downto step
      ].to_set.freeze

      # What a row key's Ruby may consist of, so that reading it before the row
      # renders cannot change what the row renders: the loop's own variables,
      # literals, and calls made on them (todo.id, todo[:id], dom_id(todo)).
      KEY_NODES = [
        Prism::ProgramNode, Prism::StatementsNode, Prism::ArgumentsNode, Prism::ParenthesesNode,
        Prism::StringNode, Prism::SymbolNode, Prism::IntegerNode, Prism::LocalVariableReadNode, Prism::CallNode
      ].freeze
      RECEIVERLESS_KEY_CALLS = %i[dom_id].freeze

      KEY_ATTRIBUTES = %w[live-key id].freeze
      OPAQUE_MARKERS = %i[opaque_open opaque_close].freeze

      # @param structured [Boolean] Whether top-level control blocks compile
      #   to nodes rather than HTML strings
      def initialize(engine, options = {}, structured: LiveCable.configuration.structured_blocks)
        super(engine, options)

        @structured = structured
        @opaque_depth = 0
        @next_tag = nil
        @next_scope_id = 0
        @in_subsequent = false
        @output_seen = false
      end

      # Sentinel tokens carry a "\n" value so herb's whitespace helpers
      # (at_line_start?, preceding_token_ends_with_newline?) treat them like
      # a line boundary instead of crashing on a nil value.
      def visit_erb_control_node(node, &block)
        tag = @next_tag
        @next_tag = nil

        @tokens << [:block_start, "\n"]
        super do
          tag_code_token(tag) if tag && node.content
          block&.call
        end
        @tokens << [:block_end, "\n"]
      end

      def visit_erb_block_node(node)
        if !structuring?
          wrap_block { super }
        elsif iteration?(node)
          wrap_block do
            visit_loop(node) { visit_all(node.body) }
          end
        else
          wrap_block(:opaque) do
            opaque { super }
          end
        end
      end

      def visit_erb_if_node(node)
        return super unless structuring?

        if @in_subsequent
          @in_subsequent = false
          branch(node) do
            visit_all(node.statements)
            visit_subsequent(node.subsequent)
          end
        else
          conditional(node) do
            visit_all(node.statements)
            visit_subsequent(node.subsequent)
          end
        end
      end

      def visit_erb_else_node(node)
        return super unless structuring?

        branch(node) { visit_all(node.statements) }
      end

      def visit_erb_unless_node(node)
        return super unless structuring?

        conditional(node) do
          visit_all(node.statements)
          visit(node.else_clause)
        end
      end

      def visit_erb_case_node(node)
        return super unless structuring?

        case_conditional(node)
      end

      def visit_erb_case_match_node(node)
        return super unless structuring?

        case_conditional(node)
      end

      def visit_erb_when_node(node)
        return super unless structuring?

        branch(node) { visit_all(node.statements) }
      end

      def visit_erb_in_node(node)
        return super unless structuring?

        branch(node) { visit_all(node.statements) }
      end

      def visit_erb_for_node(node)
        return super unless structuring?

        visit_loop(node) { visit_all(node.statements) }
      end

      def visit_erb_while_node(node)
        return super unless structuring?

        visit_loop(node) { visit_all(node.statements) }
      end

      def visit_erb_until_node(node)
        return super unless structuring?

        visit_loop(node) { visit_all(node.statements) }
      end

      def visit_erb_begin_node(node)
        return super unless structuring?

        start = @tokens.length
        opaque { super }
        mark_opaque(start)
      end

      def generate_output
        tokens = optimize_tokens(@tokens)

        tokens.map do |type, value, context|
          if type == :block
            generate_block(value)
            @output_seen = true
          else
            generate_for_token(type, value, context)
            @output_seen ||= type != :code && (type != :text || value.match?(/\S/))
            @engine.send(:finish_method, type)
          end
        end
      end

      def generate_for_token(type, value, _context = nil, _escaped = nil, engine: @engine)
        case type
        when :text
          engine.send(:add_text, value)
        when :code, :expr_block_end
          # Escaping is delegated to Rails' output buffer, so the closing
          # `end` of an output block (:expr_block_end) is emitted as plain
          # code rather than herb's paren-balancing add_expression_block_end.
          engine.send(:add_code, value)
        when :expr
          indicator = @escape ? '==' : '='
          engine.send(:add_expression, indicator, value)
        when :expr_escaped
          indicator = @escape ? '=' : '=='
          engine.send(:add_expression, indicator, value)
        when :expr_block
          indicator = @escape ? '==' : '='
          engine.send(:add_expression_block, indicator, value)
        when :expr_block_escaped
          indicator = @escape ? '=' : '=='
          engine.send(:add_expression_block, indicator, value)
        end
      end

      # Groups everything between a top-level block's sentinels into one
      # [:block, tokens] entry. Inside a block, the sentinels around an opaque
      # construct are kept as markers for the tree builder.
      def optimize_tokens(unoptimized_tokens)
        tokens = super
        optimized_tokens = []
        block_count = 0
        current_block = []

        tokens.each do |token|
          if token[0] == :block_start
            current_block << [:opaque_open] if token[2] == :opaque && block_count.positive?
            block_count += 1
          elsif token[0] == :block_end
            block_count -= 1
            current_block << [:opaque_close] if token[2] == :opaque && block_count.positive?

            if block_count.zero?
              optimized_tokens << [:block, current_block]
              current_block = []
            end
          elsif block_count.zero?
            optimized_tokens << token
          else
            current_block << token
          end
        end

        optimized_tokens
      end

      private

      def structuring?
        @structured && @opaque_depth.zero?
      end

      # Emits a top-level block as a node when it opens with a branch or a
      # loop the tree can hold, and as one HTML part otherwise.
      #
      # A block that comes before any output may hold the component's root
      # element, which gets the root attributes inserted into its markup, so
      # it stays HTML.
      def generate_block(block_tokens)
        if @output_seen && structured_block?(block_tokens) && tree_built?(block_tokens)
          return generate_tree(block_tokens)
        end

        emit_tokens(block_tokens.reject { |token| OPAQUE_MARKERS.include?(token[0]) }, @engine)
        @engine.send(:finish_method, :block)
      end

      def tree_built?(block_tokens)
        @built = build_tree(block_tokens)
        true
      rescue TreeBuilder::Unsupported
        false
      end

      def generate_tree(_block_tokens)
        code, statics = @built
        @engine.send(:add_tree, code, statics)
        @engine.send(:finish_method, :tree)
      end

      def build_tree(block_tokens)
        TreeBuilder.new(
          block_tokens,
          raw_expression: ->(type) { raw_expression?(type) },
          opaque_code: lambda { |tokens|
            @engine.send(:buffer_code_for) { |engine| emit_tokens(tokens, engine) }
          }
        ).build
      end

      def structured_block?(block_tokens)
        first = block_tokens.find { |type, value| type != :text || !value.empty? }
        return false unless first && first[0] == :code && first[2].is_a?(Structure)

        %i[cond_open loop_open].include?(first[2].ops.first.first)
      end

      def emit_tokens(tokens, engine)
        tokens.each do |type, value, context, escaped|
          generate_for_token(type, value, context, escaped, engine:)
        end
      end

      # Mirrors Renderer#add_rails_expression: an expression goes through the
      # buffer unescaped when its indicator is == or escaping is on.
      def raw_expression?(type)
        indicator = if type == :expr
                      @escape ? '==' : '='
                    else
                      @escape ? '=' : '=='
                    end

        indicator == '==' || @escape
      end

      def conditional(node)
        @next_tag = Structure.new([[:cond_open], [:branch, next_scope_id]])
        visit_erb_control_node(node) do
          yield
          close_with(node.end_node, :cond_close)
        end
      end

      def case_conditional(node)
        @next_tag = Structure.new([[:cond_open]])
        visit_erb_control_node(node) do
          visit_all(node.conditions)
          visit(node.else_clause)
          close_with(node.end_node, :cond_close)
        end
      end

      def branch(node, &)
        @next_tag = Structure.new([[:branch, next_scope_id]])
        visit_erb_control_node(node, &)
      end

      def visit_subsequent(node)
        return unless node

        @in_subsequent = node.is_a?(Herb::AST::ERBIfNode)
        visit(node)
      end

      def visit_loop(node)
        body = node.respond_to?(:body) ? node.body : node.statements
        @next_tag = Structure.new([[:loop_open, next_scope_id, key_code_for(body, loop_variables(node))]])

        visit_erb_control_node(node) do
          yield
          close_with(node.end_node, :loop_close)
        end
      end

      def close_with(end_node, op)
        return unless end_node

        @next_tag = Structure.new([[op]])
        visit(end_node)
      end

      # The extra sentinel pair every block gets, as it always has. An opaque
      # block's pair is marked so the tree builder can capture it.
      def wrap_block(marker = nil)
        @tokens << [:block_start, "\n", marker]
        yield
        @tokens << [:block_end, "\n", marker]
      end

      def opaque
        @opaque_depth += 1
        yield
      ensure
        @opaque_depth -= 1
      end

      def mark_opaque(start)
        opening = (start...@tokens.length).find { |index| @tokens[index][0] == :block_start }
        closing = (start...@tokens.length).reverse_each.find { |index| @tokens[index][0] == :block_end }
        return unless opening && closing

        @tokens[opening] = [:block_start, "\n", :opaque]
        @tokens[closing] = [:block_end, "\n", :opaque]
      end

      def tag_code_token(tag)
        token = @tokens.last
        return unless token && token[0] == :code

        @tokens[-1] = [:code, token[1], tag]
      end

      def iteration?(node)
        return false if node.tag_opening.value.include?('=')
        return false if node.rescue_clause || node.else_clause || node.ensure_clause

        call = block_call(node.content.value.strip)
        call && ITERATION_METHODS.include?(call.name)
      end

      # The call that owns the block a block tag opens, parsed with the block
      # closed, or nil.
      def block_call(code)
        ["\nend", "\n}"].each do |closer|
          result = Prism.parse("#{code}#{closer}")
          next unless result.success?

          statement = result.value.statements.body.first
          return statement if statement.is_a?(Prism::CallNode) && statement.block.is_a?(Prism::BlockNode)
        end

        nil
      end

      # The variables a loop binds for each row: a block's parameters or a
      # for loop's index. A while or until loop binds none.
      def loop_variables(node)
        code = node.content&.value.to_s.strip

        case node
        when Herb::AST::ERBBlockNode
          block_call(code)&.block&.locals || []
        when Herb::AST::ERBForNode
          result = Prism.parse("#{code}\nend")
          result.success? ? result.value.locals : []
        else
          []
        end
      end

      def next_scope_id
        id = @next_scope_id
        @next_scope_id += 1
        id
      end

      # The key of a loop's rows: the live-key or id of the one element its
      # body renders, when that attribute has Ruby in it. Nothing else may sit
      # in the body, because the key is read before the body runs.
      def key_code_for(body, variables)
        return if variables.empty?

        significant = Array(body).reject do |child|
          child.is_a?(Herb::AST::WhitespaceNode) ||
            (child.is_a?(Herb::AST::HTMLTextNode) && child.content.strip.empty?) ||
            !child.class.name.start_with?('Herb::AST::HTML', 'Herb::AST::ERB')
        end

        element = significant.first
        return unless significant.one? && element.is_a?(Herb::AST::HTMLElementNode)

        attribute = element.open_tag.children.grep(Herb::AST::HTMLAttributeNode).find do |candidate|
          KEY_ATTRIBUTES.include?(attribute_name(candidate))
        end

        attribute && attribute_value_code(attribute, variables)
      end

      def attribute_name(attribute)
        attribute.name.children.map { |child| child.respond_to?(:content) ? child.content : '' }.join.downcase
      end

      def attribute_value_code(attribute, variables)
        return unless attribute.value

        parts = attribute.value.children.map do |child|
          case child
          when Herb::AST::LiteralNode
            child.content.inspect
          when Herb::AST::ERBContentNode
            code = child.content.value.strip
            return nil unless child.tag_opening.value.start_with?('<%=') && pure_read?(code, variables)

            "(#{code}\n).to_s"
          else
            return nil
          end
        end

        return unless parts.any? { |part| part.end_with?('.to_s') }

        "[#{parts.join(', ')}].join"
      end

      def pure_read?(code, variables)
        result = Prism.parse(code)
        result.success? && pure_node?(result.value, variables)
      end

      def pure_node?(node, variables)
        return false unless KEY_NODES.any? { |type| node.is_a?(type) }
        return variables.include?(node.name) if node.is_a?(Prism::LocalVariableReadNode)

        if node.is_a?(Prism::CallNode)
          return false if node.block
          return variables.include?(node.name) if node.variable_call?
          return false if node.receiver.nil? && !RECEIVERLESS_KEY_CALLS.include?(node.name)
          return false if node.name.end_with?('=', '!')
        end

        node.compact_child_nodes.all? { |child| pure_node?(child, variables) }
      end
    end
  end
end
