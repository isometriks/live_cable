# frozen_string_literal: true

require 'prism'

module LiveCable
  module Rendering
    # Compile-time pieces of collection streams. A stream is written
    #
    #   <ul live-stream="messages">
    #     <%= live_stream_for :messages do |message| %>
    #       <li><%= message.body %></li>
    #     <% end %>
    #   </ul>
    #
    # and compiles to a keyed loop node whose rows the server doesn't keep:
    # the row body becomes a method on the renderer class, so one row can be
    # rendered without running the template (see Compiler, TreeBuilder and
    # Partial).
    module Streams
      HELPER = :live_stream_for
      KEY = '__lc_stream_key'
      NAME = /\A[a-z_][a-z0-9_]*\z/
      FORM = '<%= live_stream_for :name do |row| %>…<% end %>'

      # Where a stream is rendered, as the template and its metadata describe it
      Stream = Data.define(:name, :part, :path, :scope, :virtual_path, :user_id_code, :key_id) do
        def row_method = :"__lc_stream_row_#{scope}"

        # The row's own id attribute, for the development check
        def id_method = :"__lc_stream_id_#{scope}"
      end

      # A `live_stream_for` block tag
      class Call
        # @return [Symbol]
        attr_reader :name

        # @return [Symbol] The row's block parameter
        attr_reader :param

        # @return [String] file:line
        attr_reader :location

        # The block tag's receiverless live_stream_for call, or nil
        #
        # @param node [Herb::AST::ERBBlockNode]
        # @return [Prism::CallNode, nil]
        def self.call_node(node)
          code = node.content&.value.to_s.strip
          return unless code.include?(HELPER.to_s)

          ["\nend", "\n}"].each do |closer|
            result = Prism.parse("#{code}#{closer}")
            next unless result.success?

            statement = result.value.statements.body.first
            return statement if statement.is_a?(Prism::CallNode) && statement.receiver.nil? &&
                                statement.name == HELPER && statement.block.is_a?(Prism::BlockNode)
          end

          nil
        end

        # @return [Call, nil] The checked call, or nil when the tag isn't one
        def self.parse(node, location)
          call = call_node(node) or return
          new(node, call, location)
        end

        def initialize(node, call, location)
          @location = location
          check_tag!(node, call)
          @name = read_name(call)
          @param = read_param(call.block)
        end

        def error!(message)
          raise CompileError, "#{location}: #{message}"
        end

        private

        def shape_error!(problem)
          error!("write `live_stream_for` as #{FORM}: #{problem}")
        end

        def check_tag!(node, call)
          opening = node.tag_opening.value
          shape_error!("it needs an output tag (<%=), not #{opening}") unless opening.include?('=')
          shape_error!('its block needs do … end, not braces') if call.block.opening == '{'
          return unless node.rescue_clause || node.else_clause || node.ensure_clause

          shape_error!("its block can't have rescue, else or ensure")
        end

        def read_name(call)
          arguments = call.arguments&.arguments || []
          name = arguments.first.unescaped if arguments.one? && arguments.first.is_a?(Prism::SymbolNode)
          unless name
            shape_error!("its only argument is the stream's name, as a Symbol literal " \
                         "(got #{call.arguments&.slice || 'none'})")
          end
          shape_error!("stream names are lowercase snake_case (got :#{name})") unless name.match?(NAME)

          name.to_sym
        end

        def read_param(block)
          parameters = block.parameters
          params = parameters.parameters if parameters.is_a?(Prism::BlockParametersNode)
          found = parameters ? parameters.slice : 'none'

          if params.nil? || params.requireds.size != 1 || !params.requireds.first.is_a?(Prism::RequiredParameterNode) ||
             params.optionals.any? || params.rest || params.posts.any? || params.keywords.any? ||
             params.keyword_rest || params.block
            shape_error!("its block takes exactly one parameter, the row (got #{found})")
          end

          params.requireds.first.name
        end
      end

      # The locals a row can't see because it renders on its own: those of
      # the template, the part around the stream, and live partials it sits in.
      class CallSiteLocals < Prism::Visitor
        def self.at(program, scope)
          visitor = new(scope)
          program.accept(visitor)
          program.locals | visitor.locals
        end

        attr_reader :locals

        def initialize(scope)
          super()
          @scope = scope
          @blocks = []
          @locals = []
        end

        def visit_block_node(node)
          @blocks.push(node.locals)
          super
        ensure
          @blocks.pop
        end

        def visit_call_node(node)
          scope = node.arguments&.arguments&.[](1)
          if node.name == :__lc_stream && node.receiver.nil? && scope.is_a?(Prism::IntegerNode) &&
             scope.value == @scope
            @locals = @blocks.flatten
          end

          super
        end
      end

      # What a row may not do, because it renders on its own when an op
      # arrives: read or assign the template's locals, render live
      # components, provide content, or use instance variables.
      class RowCheck < Prism::Visitor
        VIEW_FLOW = %i[content_for provide].freeze

        # @param stream [Hash] The stream's compiled metadata
        # @param locals [Array<Symbol>] Locals at the call site
        def self.check!(stream, locals)
          result = Prism.parse(stream[:code], scopes: [[stream[:param], KEY.to_sym]])
          result.value.accept(new(stream, locals - [stream[:param]]))
        end

        def initialize(stream, locals)
          super()
          @stream = stream
          @locals = locals.reject { |name| name.start_with?('__lc_') }
          @depth = 0
        end

        def visit_block_node(node) = nested { super }

        def visit_lambda_node(node) = nested { super }

        def visit_def_node(node) = nested { super }

        def visit_call_node(node)
          if node.receiver.nil?
            if node.variable_call? && @locals.include?(node.name)
              local_error!("reads `#{node.name}`, a template local")
            elsif node.name == :live
              error!('calls `live`: live components inside rows are not supported. Render the component ' \
                     'outside the stream')
            elsif node.name == :render && component_render?(node)
              error!("renders a component (`#{node.slice}`): live components inside rows are not supported. " \
                     'Render the component outside the stream')
            elsif VIEW_FLOW.include?(node.name)
              error!("calls `#{node.name}`: a row renders on its own, after the page and the template have " \
                     'rendered, so content it provides goes nowhere')
            end
          end

          super
        end

        %i[write operator_write and_write or_write target].each do |kind|
          define_method(:"visit_local_variable_#{kind}_node") do |node|
            if node.depth == @depth && @locals.include?(node.name)
              local_error!("assigns `#{node.name}`, a template local")
            end

            super(node)
          end
        end

        %i[read write operator_write and_write or_write target].each do |kind|
          define_method(:"visit_instance_variable_#{kind}_node") do |node|
            next super(node) if node.name == :@output_buffer

            error!("uses #{node.name}: part code runs on LiveCable's renderer, not the view, so instance " \
                   "variables are not the ones the page set. Read it from `#{@stream[:param]}` or a " \
                   'component method')
          end
        end

        private

        def nested
          @depth += 1
          yield
        ensure
          @depth -= 1
        end

        # Only a constant that resolves now; the render-time check catches the rest
        def component_render?(node)
          first = node.arguments&.arguments&.first
          first = first.receiver if first.is_a?(Prism::CallNode) && first.name == :new
          return false unless first.is_a?(Prism::ConstantReadNode) || first.is_a?(Prism::ConstantPathNode)

          constant = Object.const_get(first.full_name)
          constant.is_a?(Class) && constant <= LiveCable::Component
        rescue NameError, Prism::ConstantPathNode::DynamicPartsInConstantPathError
          false
        end

        def local_error!(problem)
          param = @stream[:param]
          error!("#{problem}. Rows render on their own when ops arrive, so they can read only `#{param}` and " \
                 "the component: use a component method, or compute it from `#{param}`")
        end

        def error!(problem)
          raise CompileError, "#{@stream[:location]}: the row of stream :#{@stream[:name]} #{problem}"
        end
      end

      # `stream(:messages).each` and the like, which read as an enumeration
      # of rows a stream doesn't hold.
      class EnumerationCheck < Prism::Visitor
        # What closes an opening tag's code, or opens a branch's, so it parses
        WRAPPINGS = [
          ['', ''], ['', "\nend"], ['', "\n}"], ['', "\nwhen nil\nend"], ["if nil\n", "\nend"], ["case nil\n", "\nend"]
        ].freeze

        def self.check!(code, location)
          return unless code.include?('stream')

          result = WRAPPINGS.lazy.map { |before, after| Prism.parse("#{before}#{code}#{after}") }.find(&:success?)
          result&.value&.accept(new(location))
        end

        def initialize(location)
          super()
          @location = location
        end

        def visit_call_node(node)
          receiver = node.receiver
          name = receiver.arguments&.arguments&.first if receiver.is_a?(Prism::CallNode)

          if receiver.is_a?(Prism::CallNode) && receiver.name == :stream && receiver.receiver.nil? &&
             receiver.arguments&.arguments&.one? && name.is_a?(Prism::SymbolNode)
            stream = name.unescaped
            raise CompileError, "#{@location}: `stream(:#{stream}).#{node.name}` reads collection stream " \
                                ":#{stream} as a list, but a stream holds no rows. Render it with " \
                                "<%= live_stream_for :#{stream} do |row| %>…<% end %> inside an element with " \
                                "live-stream=\"#{stream}\""
          end

          super
        end
      end
    end
  end
end
