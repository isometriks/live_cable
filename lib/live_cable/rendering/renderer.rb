# frozen_string_literal: true

module LiveCable
  module Rendering
    class Renderer < ::Herb::Engine
      # rubocop:disable Lint/MissingSuper
      def initialize
        @newline_pending = 0
        @parts = []
        @statics = {}
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
        "::LiveCable::Rendering::Partial.new(#{parts.inspect}, #{metadata.inspect}, #{statics.inspect})"
      end

      private

      # @return [Integer]
      attr_reader :newline_pending

      # @return [Array]
      attr_reader :parts

      # @return [Hash{Integer=>Array<String>}] The statics of every tree part's scopes
      attr_reader :statics

      # @return [String]
      attr_reader :bufvar

      # @return [String]
      attr_reader :text_end

      def build_metadata
        accumulated_locals = [] # Track locals defined in previous parts

        parts.map do |type, code|
          next nil if type == :static || code.nil? || code.empty?

          parsed = Prism.parse(code).value
          locals_defined_here = user_names(parsed.locals || [])
          local_check_code = +''

          locals_defined_here.each do |local|
            local_check_code << "store_local(:#{local}, #{local}) if defined?(#{local})\n"
          end

          visitor = DependencyVisitor.new
          visitor.visit(parsed)

          local_reads = user_names(visitor.local_reads)
          local_writes = user_names(visitor.local_writes)

          # Component/method dependencies: reads that aren't locals from previous parts
          component_dependencies = local_reads - accumulated_locals

          # Local dependencies: reads that ARE from previous parts
          local_dependencies = local_reads & accumulated_locals

          # Track component.method_name calls separately for runtime expansion
          component_method_calls = user_names(visitor.component_method_calls.to_a)

          # Add locals defined in this part to accumulated list for next parts
          accumulated_locals |= local_writes

          {
            type:,
            code:,
            component_dependencies: component_dependencies - [:component],
            component_method_calls:,
            local_dependencies:,
            defines_locals: local_writes,
            local_check_code:,
          }
        end
      end

      # The names a tree part's bookkeeping uses (TreeBuilder) are not the
      # template's, so they never count as dependencies or locals.
      def user_names(names)
        names.reject { |name| name.start_with?('__lc_') }
      end

      # Adds a tree part's code, which returns its node, and its statics.
      # Newlines Herb held back from the previous text part would otherwise
      # land in the node's code, where nothing writes them, so they become a
      # text part of their own first.
      def add_tree(code, tree_statics)
        if newline_pending.positive?
          flush_newline_if_pending(@src)
          finish_method(:text)
        end

        @src << code
        statics.merge!(tree_statics)
      end

      # Ruby that writes to @output_buffer the way a plain part does, for a
      # construct inside a tree part that is captured to HTML.
      def buffer_code_for
        engine = self.class.new
        yield engine
        engine.send(:flush_newline_if_pending, engine.send(:pending_src))
        engine.send(:pending_src)
      end

      def pending_src
        @src
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
