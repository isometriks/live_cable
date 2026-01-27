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
        metadata = build_metadata
        "::LiveCable::Rendering::Partial.new(#{@parts.inspect}, #{metadata.inspect})"
      end

      private

      def build_metadata
        @parts.map do |type, code|
          next nil if type == :static || code.nil? || code.empty?

          parsed = Prism.parse(code).value
          locals = parsed.locals || []
          local_check_code = +''

          locals.each do |local|
            local_check_code << "store_local(:#{local}, #{local}) if defined?(#{local})\n"
          end

          visitor = DependencyVisitor.new
          visitor.visit(parsed)

          {
            type: type,
            code: code,
            dependencies: visitor.dependencies,
            local_check_code: local_check_code
          }
        end
      end

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
