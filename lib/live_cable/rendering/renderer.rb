# frozen_string_literal: true

module LiveCable
  module Rendering
    class Renderer < ::Herb::Engine
      # rubocop:disable Lint/MissingSuper
      def initialize
        @newline_pending = 0
        @parts = []
        @src = +''

        @bufvar = '@output_buffer'
        @src = String.new
        @chain_appends = nil
        @buffer_on_stack = false
        @debug = false
        @text_end = "'"
      end
      # rubocop:enable Lint/MissingSuper

      def src
        "::LiveCable::Rendering::Partial.new(#{@parts.inspect})"
      end

      private

      def finish_method(type)
        @parts << [type, @src]
        @src = +''
      end

      def add_text(text)
        return if text.empty?

        if text == "\n"
          @newline_pending += 1
        else
          with_buffer do
            @src << ".safe_append='"
            @src << ("\n" * @newline_pending) if @newline_pending.positive?
            @src << text.gsub(/['\\]/, '\\\\\&') << @text_end
          end

          @newline_pending = 0
        end
      end

      def add_expression(indicator, code)
        add_rails_expression(indicator, code, wrap_parentheses: true)
      end

      def add_expression_block(indicator, code)
        add_rails_expression(indicator, code, wrap_parentheses: false)
      end

      def add_rails_expression(indicator, code, wrap_parentheses:)
        flush_newline_if_pending(@src)

        with_buffer do
          @src << if (indicator == '==') || @escape
                    '.safe_expr_append='
                  else
                    '.append='
                  end

          if wrap_parentheses
            @src << '(' << code << ')'
          else
            @src << ' ' << code
          end
        end
      end

      def add_code(code)
        flush_newline_if_pending(@src)
        super
      end

      def add_postamble(_)
        flush_newline_if_pending(@src)
        super
      end

      def flush_newline_if_pending(src)
        return unless @newline_pending.positive?

        with_buffer { src << ".safe_append='#{"\n" * @newline_pending}" << @text_end }
        @newline_pending = 0
      end
    end
  end
end
