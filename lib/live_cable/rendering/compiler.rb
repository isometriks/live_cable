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
        Prism::StringNode, Prism::InterpolatedStringNode, Prism::EmbeddedStatementsNode, Prism::SymbolNode,
        Prism::IntegerNode, Prism::LocalVariableReadNode, Prism::CallNode
      ].freeze
      RECEIVERLESS_KEY_CALLS = %i[dom_id].freeze

      KEY_ATTRIBUTES = %w[live-key id].freeze
      OPAQUE_MARKERS = %i[opaque_open opaque_close].freeze

      # A block around the point being compiled that a stream can't sit in:
      # a loop, a stream's row, or a construct rendered to one HTML string.
      Enclosing = Struct.new(:kind, :label, :location)

      # Where the browser's parser would move rows out of their container
      STREAM_CONTAINER_TAGS = {
        'table' => 'the browser moves rows out of a <table>: put live-stream on its <tbody>',
        'p' => 'a <p> can only hold inline content: use a <div>',
      }.freeze
      FOREIGN_TAGS = %w[svg math].freeze

      # @param structured [Boolean] Whether top-level control blocks compile
      #   to nodes rather than HTML strings
      # @param live_partials [LivePartials::Inliner, nil] Inlines the live
      #   partials this file renders; nil compiles renders as plain calls
      def initialize(engine, options = {}, structured: LiveCable.configuration.structured_blocks, live_partials: nil)
        super(engine, options)

        @structured = structured
        @live_partials = live_partials
        @enclosing = []
        @stream_sites = {}
        @stream_containers = {}.compare_by_identity
        @row_root = nil
        @next_tag = nil
        @next_scope_id = 0
        @in_subsequent = false
        @output_seen = false
      end

      def visit_erb_content_node(node)
        unless !node.content || node.tag_opening.value.start_with?('<%#')
          Streams::EnumerationCheck.check!(node.content.value, location(node))
        end
        site = @live_partials&.site_for(node)
        return super unless site

        inline_partial(node, site)
      end

      # Sentinel tokens carry a "\n" value so herb's whitespace helpers
      # (at_line_start?, preceding_token_ends_with_newline?) treat them like
      # a line boundary instead of crashing on a nil value.
      def visit_erb_control_node(node, &block)
        if node.content
          @live_partials&.check!(node)
          Streams::EnumerationCheck.check!(node.content.value, location(node)) unless node.is_a?(Herb::AST::ERBBlockNode)
        end
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
        @live_partials&.check!(node)
        Streams::EnumerationCheck.check!(node.content.value, location(node))

        if (call = Streams::Call.parse(node, location(node)))
          visit_stream(node, call)
        elsif !structuring?
          wrap_block { super }
        elsif iteration?(node)
          wrap_block do
            visit_loop(node) { visit_all(node.body) }
          end
        else
          wrap_block(:opaque) do
            enclosed(:helper, construct_label(node), node) { super }
          end
        end
      end

      def visit_html_element_node(node)
        check_stream_container(node)
        super
      end

      # A stream row's root element gets the row's key as its id, first
      def visit_html_open_tag_node(node)
        return super unless @row_root.equal?(node)

        @row_root = nil
        add_text(node.tag_opening&.value || '<')
        add_text(node.tag_name.value)
        add_text(' id="')
        add_expression_with_escaping(Streams::KEY, should_escape_output?('<%='))
        add_text('"')
        visit_all(node.children)
        add_text(node.tag_closing&.value || '>')
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
        enclosed(:begin, 'begin', node) { super }
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

      protected

      # A live partial's compiler sits where its render does
      def enter(parent, enclosing)
        @enclosing = enclosing
        @stream_sites = parent.stream_sites
        @row_root = parent.row_root
        @element_stack = parent.element_stack.dup
      end

      attr_reader :stream_sites, :row_root, :element_stack

      # Scope ids are unique across the template and every partial in it
      def scope_counter = @next_scope_id

      def scope_counter=(value)
        @next_scope_id = value
      end

      private

      # Copies a live partial's tokens in place of the <%= render %> tag, inside
      # a block that yields once (see LivePartials). The partial compiles on its
      # own first, as Rails would compile it, so its whitespace is its own.
      #
      # Inside a control block its markup joins the block's tree; at the top of
      # the template it becomes a tree of its own, or a collection's loop.
      def inline_partial(node, site)
        # What Herb does before an output tag
        if @trim_next_whitespace && @pending_leading_whitespace
          restore_pending_leading_whitespace!
          @pending_leading_whitespace = nil
          @trim_next_whitespace = false
          @last_trim_consumed_newline = false
        end

        opening, closing = partial_structure(site)

        nested = self.class.new(@engine, { escape: @escape }, structured: @structured,
          live_partials: @live_partials.nested(site.file))
        enclosing = @enclosing
        enclosing += [Enclosing.new(:loop, 'render collection:', location(node))] if site.collection?
        nested.enter(self, enclosing)
        nested.scope_counter = scope_counter
        site.file.ast.accept(nested)
        self.scope_counter = nested.scope_counter

        @tokens << [:block_start, "\n"]
        @tokens << [:code, site.opening, opening || current_context]
        @tokens.concat(nested.tokens)
        @tokens << [:code, site.closing, closing || current_context]
        @tokens << [:block_end, "\n", :partial_end]

        @last_trim_consumed_newline = false
        @trim_next_whitespace = true if right_trim?(node)
      end

      def partial_structure(site)
        return unless structuring?

        if site.collection?
          key = key_code_for(partial_body(site.file), [site.as])
          [Structure.new([[:loop_open, next_scope_id, key]]), Structure.new([[:loop_close]])]
        else
          [Structure.new([[:partial_open, next_scope_id, site.file.virtual_path]]), Structure.new([[:partial_close]])]
        end
      end

      def partial_body(file)
        file.ast.children.reject do |child|
          child.is_a?(Herb::AST::ERBContentNode) && child.tag_opening.value.start_with?('<%#')
        end
      end

      # After a live partial, Herb's whitespace rules see an output tag, not
      # the line break its sentinel token carries.
      def at_line_start?
        return @last_trim_consumed_newline if partial_end?(@tokens.last)

        super
      end

      def preceding_token_ends_with_newline?
        return @last_trim_consumed_newline if @tokens.length >= 2 && partial_end?(@tokens[-2])

        super
      end

      def partial_end?(token)
        token && token[0] == :block_end && token[2] == :partial_end
      end

      def structuring?
        @structured && @enclosing.none? { |construct| %i[helper begin].include?(construct.kind) }
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

        stream = block_tokens.find { |type, _, context| type == :code && stream_open?(context) }
        unbuilt_stream!(stream[2].ops.first, block_tokens) if stream

        emit_tokens(block_tokens.reject { |token| OPAQUE_MARKERS.include?(token[0]) }, @engine)
        @engine.send(:finish_method, :block)
      end

      def tree_built?(block_tokens)
        @built = build_tree(block_tokens)
        true
      rescue TreeBuilder::Unsupported => e
        @unsupported = e.message
        false
      end

      def generate_tree(_block_tokens)
        code, statics, streams = @built
        @engine.send(:add_tree, code, statics, streams)
        @engine.send(:finish_method, :tree)
      end

      def stream_open?(context)
        context.is_a?(Structure) && context.ops.first.first == :stream_open
      end

      # A block with a stream never falls back to HTML: the stream's rows
      # would have nowhere to go.
      def unbuilt_stream!(op, block_tokens)
        _, _, name, _, _, at = op
        reason = if !@output_seen
                   'is in a block that opens the template, which renders to one HTML string. Put the ' \
                     "template's content in a root element"
                 elsif !structured_block?(block_tokens)
                   "is in a block the compiler can't split into a tree. Put it directly inside an " \
                     'if, unless or case, or at the top of the template'
                 elsif @unsupported == 'control flow leaves a scope early'
                   "is in a block that uses next, break, return, redo, retry or throw, which can't be split " \
                     'into a tree. Remove them from the block and the row'
                 elsif @unsupported == 'conditional used as a value'
                   'is in a conditional used as a value (`x = if …`). Write the conditional as its own tag'
                 else
                   "is in a block the compiler can't split into a tree (#{@unsupported})"
                 end

        raise CompileError, "#{at}: stream :#{name} #{reason}"
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

        %i[cond_open loop_open partial_open stream_open].include?(first[2].ops.first.first)
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

        enclosed(:loop, loop_label(node), node) do
          visit_erb_control_node(node) do
            yield
            close_with(node.end_node, :loop_close)
          end
        end
      end

      # A stream's row compiles like a loop body, tagged :stream_open and
      # :stream_close so the tree builder gives it code of its own.
      def visit_stream(node, call)
        check_stream_placement!(call)
        unless @stream_containers.delete(node)
          call.error!("live_stream_for :#{call.name} must be the only content of an element with " \
                      "live-stream=\"#{call.name}\", such as <ul live-stream=\"#{call.name}\">")
        end

        if (other = @stream_sites[call.name])
          call.error!("stream :#{call.name} is also rendered at #{other}: a template renders each stream " \
                      'from one place')
        end
        @stream_sites[call.name] = call.location

        root, user_id_code = stream_row_root(node, call)
        scope = next_scope_id
        outer_root = @row_root
        @row_root = root

        enclosed(:row, "the row of stream :#{call.name}", node) do
          wrap_block do
            @next_tag = Structure.new([[:stream_open, scope, call.name, call.param, user_id_code, call.location]])
            visit_erb_control_node(node) do
              visit_all(node.body)
              close_with(node.end_node, :stream_close)
            end
          end
        end
      ensure
        @row_root = outer_root
      end

      def check_stream_placement!(call)
        unless @structured
          call.error!("collection streams need structured blocks: stream :#{call.name} can't compile with " \
                      'config.structured_blocks = false')
        end

        construct = @enclosing.last
        return unless construct

        reason = case construct.kind
                 when :loop, :row
                   'a stream needs exactly one container, so it renders once, outside any loop'
                 when :begin
                   'begin/rescue renders to one HTML string. Rescue in a component method instead'
                 else
                   'block helpers render to one HTML string. Use a plain element: `<form live-form="…">` ' \
                   'instead of `form_with`, or `<section class="…">` instead of `tag.section do`'
                 end

        where = construct.kind == :row ? construct.label : "`#{construct.label}`"
        call.error!("stream :#{call.name} can't sit inside #{where} (#{construct.location}): #{reason}")
      end

      # The element whose sole content is a stream is its container. Its
      # live-stream attribute must name the stream, statically.
      def check_stream_container(node)
        open_tag = node.open_tag
        body = significant_children(node.body)
        stream = body.first if body.one? && body.first.is_a?(Herb::AST::ERBBlockNode)
        call = Streams::Call.call_node(stream) if stream
        name = call.arguments&.arguments&.first if call
        name = name.unescaped if name.is_a?(Prism::SymbolNode)
        name = nil unless name.is_a?(String) && name.match?(Streams::NAME)
        attribute = live_stream_attribute(open_tag)
        at = location(node)

        unless call
          return unless attribute

          if node.body.any? { |child| child.is_a?(Herb::AST::ERBBlockNode) && Streams::Call.call_node(child) }
            raise CompileError, "#{at}: an element with live-stream must contain nothing but its " \
                                'live_stream_for call (whitespace and ERB comments aside)'
          end

          value = static_attribute_value(attribute) || 'name'
          raise CompileError, "#{at}: <#{node.tag_name&.value} live-stream=\"#{value}\"> has no live_stream_for " \
                              "call: its only content must be <%= live_stream_for :#{value} do |row| %>…<% end %>"
        end

        tag = node.tag_name&.value&.downcase
        problem = if !open_tag.is_a?(Herb::AST::HTMLOpenTagNode)
                    'its container opens with a conditional tag. Write one open tag, with a dynamic class ' \
                      'if it must differ'
                  elsif (reason = STREAM_CONTAINER_TAGS[tag])
                    "can't use a <#{tag}> as its container: #{reason}"
                  elsif (foreign = (@element_stack + [tag]).find { |ancestor| FOREIGN_TAGS.include?(ancestor) })
                    "can't sit inside <#{foreign}>: its rows would be parsed as #{foreign.upcase} elements"
                  elsif attribute.nil?
                    "needs its container, <#{tag}>, to have live-stream=\"#{name}\""
                  elsif (value = static_attribute_value(attribute)).nil?
                    "needs a static live-stream on its container, written live-stream=\"#{name}\""
                  elsif value != name
                    "is in <#{tag} live-stream=\"#{value}\">: its live-stream must be \"#{name}\""
                  end

        raise CompileError, "#{at}: stream :#{name} #{problem}" if problem && name

        @stream_containers[stream] = node
      end

      def live_stream_attribute(open_tag)
        return unless open_tag.respond_to?(:children)

        open_tag.children.grep(Herb::AST::HTMLAttributeNode).find { |attribute| attribute_name(attribute) == 'live-stream' }
      end

      def static_attribute_value(attribute)
        children = attribute.value&.children || []
        return unless children.all?(Herb::AST::LiteralNode)

        children.map(&:content).join
      end

      # The one element a stream's row renders, which gets the row's key as
      # its id unless it has an id of its own. A live partial's element
      # counts, since the partial is inlined.
      #
      # @return [Array(Herb::AST::HTMLOpenTagNode, String)] The open tag to
      #   put the key in (nil when the row has its own id), and Ruby that
      #   reads the row's own id (nil when it has none, or it is a partial's)
      def stream_row_root(node, call)
        element, variables = row_element(node.body, @live_partials, call, [call.param])
        open_tag = element.open_tag
        unless open_tag.is_a?(Herb::AST::HTMLOpenTagNode)
          call.error!("the row of stream :#{call.name} opens its element with a conditional tag: write one " \
                      'open tag, with a dynamic class if it must differ')
        end

        id = open_tag.children.grep(Herb::AST::HTMLAttributeNode).find { |attribute| attribute_name(attribute) == 'id' }
        return [open_tag, nil] unless id

        if static_attribute_value(id)
          call.error!("the row of stream :#{call.name} has a static id, which every row would share. Remove " \
                      'it, and each row gets its dom id as its id')
        end

        code = attribute_value_code(id, variables)
        unless code
          call.error!("the row of stream :#{call.name} has an id that reads more than " \
                      "`#{variables.join('`, `')}`. Remove it, and each row gets its dom id as its id, or " \
                      "declare `stream :#{call.name}, dom_id: ->(#{call.param}) { … }`")
        end

        [nil, variables == [call.param] ? code : nil]
      end

      # Code tags write nothing, so they may sit around the element
      def row_element(children, inliner, call, variables)
        significant = significant_children(children, code: true)
        child = significant.first

        if significant.one?
          return [child, variables] if child.is_a?(Herb::AST::HTMLElementNode)

          site = inliner.site_for(child) if inliner && child.is_a?(Herb::AST::ERBContentNode)
          if site && !site.collection?
            return row_element(partial_body(site.file), inliner.nested(site.file), call, site.file.signature.names)
          end
        end

        found = if significant.empty?
                  'it renders nothing'
                elsif !significant.one?
                  "it has #{significant.size} at its top level"
                elsif child.is_a?(Herb::AST::HTMLTextNode)
                  'it is bare text'
                else
                  "it is `#{child.respond_to?(:content) ? child.content.value.strip : child.class.name}`, which " \
                    "the compiler can't see into. Write the row's root element in the template and render " \
                    'the partial inside it, or make the partial a live partial'
                end

        call.error!("the row of stream :#{call.name} must render exactly one element: #{found}")
      end

      def significant_children(children, code: false)
        Array(children).reject do |child|
          child.is_a?(Herb::AST::WhitespaceNode) ||
            (child.is_a?(Herb::AST::HTMLTextNode) && child.content.strip.empty?) ||
            (child.is_a?(Herb::AST::ERBContentNode) &&
              (child.tag_opening.value.start_with?('<%#') || (code && !child.tag_opening.value.include?('='))))
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

      def enclosed(kind, label, node)
        @enclosing += [Enclosing.new(kind, label, location(node))]
        yield
      ensure
        @enclosing = @enclosing[0...-1]
      end

      def location(node)
        file = @live_partials&.identifier || @engine.send(:identifier) || 'template'
        "#{file}:#{node.location.start.line}"
      end

      def construct_label(node)
        code = node.content.value.strip.sub(/\A[a-z_]\w*\s*=(?!=)\s*/, '')
        code[/\A[\w.:]+[?!]?/] || code
      end

      def loop_label(node)
        case node
        when Herb::AST::ERBBlockNode then block_call(node.content.value.strip).name.to_s
        when Herb::AST::ERBForNode then 'for'
        when Herb::AST::ERBWhileNode then 'while'
        else 'until'
        end
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
