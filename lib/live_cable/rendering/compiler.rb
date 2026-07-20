# frozen_string_literal: true

module LiveCable
  module Rendering
    class Compiler < ::Herb::Engine::Compiler
      # Sentinel tokens carry a "\n" value so herb's whitespace helpers
      # (at_line_start?, preceding_token_ends_with_newline?) treat them like
      # a line boundary instead of crashing on a nil value.
      def visit_erb_control_node(node)
        @tokens << [:block_start, "\n"]
        super
        @tokens << [:block_end, "\n"]
      end

      def visit_erb_block_node(node)
        @tokens << [:block_start, "\n"]
        super
        @tokens << [:block_end, "\n"]
      end

      def generate_output
        tokens = optimize_tokens(@tokens)

        tokens.map do |type, value, context|
          if type == :block
            value.map { |token| generate_for_token(*token) }
          else
            generate_for_token(type, value, context)
          end

          @engine.send(:finish_method, type)
        end
      end

      def generate_for_token(type, value, _context = nil, _escaped = nil)
        case type
        when :text
          @engine.send(:add_text, value)
        when :code, :expr_block_end
          # Escaping is delegated to Rails' output buffer, so the closing
          # `end` of an output block (:expr_block_end) is emitted as plain
          # code rather than herb's paren-balancing add_expression_block_end.
          @engine.send(:add_code, value)
        when :expr
          indicator = @escape ? '==' : '='
          @engine.send(:add_expression, indicator, value)
        when :expr_escaped
          indicator = @escape ? '=' : '=='
          @engine.send(:add_expression, indicator, value)
        when :expr_block
          indicator = @escape ? '==' : '='
          @engine.send(:add_expression_block, indicator, value)
        when :expr_block_escaped
          indicator = @escape ? '=' : '=='
          @engine.send(:add_expression_block, indicator, value)
        end
      end

      def optimize_tokens(unoptimized_tokens)
        tokens = super
        optimized_tokens = []
        block_count = 0
        current_block = []

        tokens.each do |token|
          if token[0] == :block_start
            block_count += 1
          elsif token[0] == :block_end
            block_count -= 1

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
    end
  end
end
