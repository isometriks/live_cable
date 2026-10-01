# frozen_string_literal: true

require 'prism'

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
        "::LiveCable::Rendering::Partial.new(#{parts.inspect}, #{metadata.inspect})"
      end

      private

      # @return [Integer]
      attr_reader :newline_pending

      # @return [Array]
      attr_reader :parts

      # @return [String]
      attr_reader :bufvar

      # @return [String]
      attr_reader :text_end

      def build_metadata
        accumulated_locals = [] # Track locals defined in previous parts

        metadata = parts.map do |type, code|
          next nil if type == :static || code.nil? || code.empty?

          # Earlier parts' locals are in scope, as they would be in one ERB method body
          parsed = Prism.parse(code, scopes: [accumulated_locals]).value

          visitor = DependencyVisitor.new
          visitor.visit(parsed)

          local_check_code = +''

          visitor.local_writes.each do |local|
            local_check_code << "store_local(:#{local}, #{local}) if defined?(#{local})\n"
          end

          # A write that doesn't run, such as one in a false `if`, keeps the earlier value
          local_dependencies = (visitor.local_reads | visitor.local_writes) & accumulated_locals

          # Track component.method_name calls separately for runtime expansion
          component_method_calls = visitor.component_method_calls.to_a

          # Add locals defined in this part to accumulated list for next parts
          accumulated_locals |= visitor.local_writes

          {
            type:,
            code:,
            component_dependencies: visitor.variable_calls - [:component],
            component_method_calls:,
            local_dependencies:,
            defines_locals: visitor.local_writes,
            local_check_code:,
          }
        end

        read_later = []
        metadata.reverse_each do |part|
          next unless part

          part[:feeds_later_parts] = part[:defines_locals].intersect?(read_later)
          read_later |= part[:local_dependencies]
        end
        metadata
      end

      def finish_method(type)
        # Skip empty parts (e.g. whitespace-only text absorbed by newline_pending).
        # Pending newlines will be flushed into the next part automatically.
        return if @src.empty?

        parts << [type, @src]
        @src = +''
      end

      def add_text(text)
        return if text.empty?

        if text == "\n"
          @newline_pending += 1
        else
          with_buffer do
            @src << ".safe_append='"
            @src << ("\n" * newline_pending) if newline_pending.positive?
            @src << text.gsub(/['\\]/, '\\\\\&') << text_end
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
        return unless newline_pending.positive?

        with_buffer { src << ".safe_append='#{"\n" * newline_pending}" << text_end }
        @newline_pending = 0
      end
    end
  end
end
