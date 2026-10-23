# frozen_string_literal: true

require 'digest'
require 'prism'

module LiveCable
  module Rendering
    class Renderer < ::Herb::Engine
      # Each socket render gets a fresh view, so a part that reads content another part provides needs both to run
      VIEW_FLOW_CALLS = %i[content_for content_for? provide].freeze

      # rubocop:disable Lint/MissingSuper
      def initialize(identifier = nil, virtual_path = nil)
        @identifier = identifier
        @virtual_path = virtual_path
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
        args = [parts, metadata, identifier, virtual_path].map(&:inspect) << '@current_template' << statics.inspect
        partial = "::LiveCable::Rendering::Partial.new(#{args.join(', ')})"
        digest = Digest::SHA256.hexdigest(partial)

        "::LiveCable::Rendering::Partial.fetch(#{(identifier || digest).inspect}, #{digest.inspect}) { #{partial} }"
      end

      private

      # @return [String, nil]
      attr_reader :identifier

      # @return [String, nil]
      attr_reader :virtual_path

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

        metadata = parts.map do |type, code|
          next nil if type == :static || code.nil? || code.empty?

          # Earlier parts' locals are in scope, as they would be in one ERB method body
          parsed = Prism.parse(code, scopes: [accumulated_locals]).value

          visitor = DependencyVisitor.new
          visitor.visit(parsed)

          local_reads = user_names(visitor.local_reads)
          local_writes = user_names(visitor.local_writes)
          local_check_code = +''

          local_writes.each do |local|
            local_check_code << "store_local(:#{local}, #{local}) if defined?(#{local})\n"
          end

          # A write that doesn't run, such as one in a false `if`, keeps the earlier value
          local_dependencies = (local_reads | local_writes) & accumulated_locals
          exposed_local_reads = visitor.exposed_local_reads & accumulated_locals

          # Track component.method_name calls separately for runtime expansion
          component_method_calls = user_names(visitor.component_method_calls.to_a)

          # Add locals defined in this part to accumulated list for next parts
          accumulated_locals |= local_writes

          {
            type:,
            code:,
            component_dependencies: user_names(visitor.variable_calls) - [:component],
            component_method_calls:,
            uses_view_flow: component_method_calls.intersect?(VIEW_FLOW_CALLS),
            local_dependencies:,
            exposed_local_reads:,
            defines_locals: local_writes,
            local_check_code:,
          }
        end

        read_later = []
        metadata.reverse_each do |part|
          next unless part

          part[:feeds_later_parts] = part[:defines_locals].intersect?(read_later)
          read_later |= part[:exposed_local_reads]
        end
        metadata
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
            @src << '(' << code << trailing_newline(code) << ')'
          else
            @src << ' ' << code << trailing_newline(code)
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
