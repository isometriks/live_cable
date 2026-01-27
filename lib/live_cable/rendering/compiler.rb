# frozen_string_literal: true

module LiveCable
  module Rendering
    class Compiler < ::Herb::Engine::Compiler
      def visit_erb_control_node(node)
        @tokens << [:block_start]
        super
        @tokens << [:block_end]
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

      def generate_for_token(type, value, context)
        case type
        when :text
          @engine.send(:add_text, value)
        when :code
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
