# frozen_string_literal: true

require 'prism'

module LiveCable
  module Rendering
    # A live partial is a `_name.html.live.erb` partial. When a component
    # template renders one with a literal path, the compiler copies the
    # partial's markup into the template (see Compiler#inline_partial) inside
    # a block that yields once:
    #
    #   <%= render 'live/chat/badge', label: title %>
    #
    #   __lc_partial("live/chat/_badge", { label: (title) }) do |local_assigns, label:, tone: ("info"); css|
    #     ...the partial's code...
    #   end
    #
    # so its reads are tracked like the template's own and, inside a control
    # block, its markup joins the block's tree. Anything that can't be copied
    # faithfully is a CompileError naming the file, the line and the fix.
    module LivePartials
      class CompileError < LiveCable::Error; end

      PARTIAL = '__lc_partial'
      COLLECTION = '__lc_partial_collection'
      WRAPPERS = [PARTIAL, COLLECTION].map(&:to_sym).freeze
      OPTIONS = %i[partial locals object as collection].freeze
      LOCAL_NAME = /\A[a-z_][a-zA-Z0-9_]*\z/

      # Herb errors that mean the partial doesn't stand on its own. Others,
      # such as an omitted </li>, compile as they would in a component template.
      STRUCTURAL_ERRORS = %w[
        MissingClosingTagError MissingOpeningTagError MissingERBEndTagError ERBControlFlowScopeError
        StrayERBClosingTagError TagNamesMismatchError UnclosedElementError
      ].filter_map { |name| Herb::Errors.const_get(name) if Herb::Errors.const_defined?(name) }.freeze

      class << self
        # @param template [ActionView::Template]
        def live?(template)
          template.handler.is_a?(Class) && template.handler <= Handler
        end

        # @param template [ActionView::Template]
        def partial?(template)
          template.virtual_path.present? && File.basename(template.virtual_path).start_with?('_')
        end

        # What a live partial compiles to on its own: it only renders inlined.
        #
        # @param template [ActionView::Template]
        # @return [String] Ruby
        def refusal(template)
          message = "#{template.short_identifier} is a live partial. It's compiled into the .live.erb template " \
                    'that renders it, so it can only be rendered from a component template with a literal path, ' \
                    "such as `render '#{render_path(template.virtual_path)}'`. Render it from the component's " \
                    'template, or use a .html.erb partial and pass locals.'

          "raise ::LiveCable::Error, #{message.inspect}"
        end

        def render_path(virtual_path)
          virtual_path.sub(%r{(\A|/)_([^/]*)\z}, '\1\2')
        end
      end

      # Finds the partial a literal path names, the way ActionView would for a
      # request that renders the calling template. The template compiles once
      # for every request, so a partial that a request variant or locale would
      # swap for another file is an error unless the caller has the same
      # variant or locale.
      class Resolver
        Details = Struct.new(:variant, :locale)

        # @param template [ActionView::Template] The component template being compiled
        def initialize(template)
          @template = template
          details = parse_details(template.short_identifier)
          @details = Details.new(details&.variant, details&.locale)
          @format = template.format || details&.format || :html
        end

        # @param path [String] A path with a directory, as written at the call site
        # @return [ActionView::Template, nil] The live partial, or nil when the
        #   path names only plain partials
        def resolve(path, site)
          candidates = find(path, variants: :any, locale: all_locales)
          live = candidates.select { |candidate| LivePartials.live?(candidate) }
          return if live.empty?

          chosen = find(path, variants: [@details.variant].compact, locale: own_locales).first
          check_duplicates!(site, chosen, candidates, live)

          live.each { |candidate| check_details!(site, candidate) }
          chosen
        end

        # A bare name resolves against the controller's prefixes, which differ
        # between the page and the socket.
        #
        # @param name [String]
        # @param from [String, nil] The virtual path of the file that renders it
        def check_bare_name!(name, from, site)
          prefixes = app_prefixes
          prefixes |= [File.dirname(from)] if from
          found = find(name, prefixes:, variants: :any, locale: all_locales).find { |t| LivePartials.live?(t) }
          return unless found

          site.error!(
            "render '#{name}' reaches live partial #{found.short_identifier}. Bare partial names resolve " \
            "against the controller's prefixes, which differ between the page and the socket; use " \
            "render '#{LivePartials.render_path(found.virtual_path)}'"
          )
        end

        private

        def check_duplicates!(site, chosen, candidates, live)
          if chosen && !LivePartials.live?(chosen)
            other = live.find { |candidate| same_details?(candidate, chosen) } || live.first
            site.error!(
              "#{chosen.short_identifier} and #{other.short_identifier} both exist, and Rails renders " \
              "#{chosen.short_identifier}. Rename or remove one of them"
            )
          end

          return unless chosen

          duplicate = candidates.find do |candidate|
            !LivePartials.live?(candidate) && same_details?(candidate, chosen)
          end
          return unless duplicate

          site.error!(
            "#{chosen.short_identifier} and #{duplicate.short_identifier} both exist, and Rails renders " \
            'the .html.erb one. Rename or remove one of them'
          )
        end

        def check_details!(site, candidate)
          details = details_of(candidate)
          return if details.variant.nil? && details.locale.nil?
          return if details == @details || caller_details.include?(details)

          missing = details.variant ? "+#{details.variant} request variant" : "#{details.locale} locale"

          site.error!(
            "#{candidate.short_identifier} would be rendered for some requests, but " \
            "#{@template.short_identifier} has no #{missing} of its own. Live partials are compiled into " \
            "their caller, so add a matching #{missing} of #{@template.short_identifier}"
          )
        end

        def caller_details
          @caller_details ||= if @template.virtual_path
                                find(@template.virtual_path, partial: false, variants: :any, locale: all_locales).
                                  map { |template| details_of(template) }
                              else
                                []
                              end
        end

        def same_details?(first, second)
          details_of(first) == details_of(second)
        end

        def details_of(template)
          details = parse_details(template.short_identifier)
          Details.new(details&.variant, details&.locale)
        end

        def find(path, variants:, locale:, prefixes: [], partial: true)
          context = ActionView::LookupContext.new(view_paths, formats: [@format], variants:, locale:)
          context.disable_cache { context.find_all(path, prefixes, partial) }
        end

        # ActionView's own parser for a template's details; it is :nodoc:, so
        # it is only reached from here.
        def parse_details(identifier)
          ActionView::Resolver::PathParser.new.parse(identifier).details
        rescue StandardError
          nil
        end

        def own_locales
          [@details.locale, I18n.default_locale].compact.uniq
        end

        def all_locales
          (I18n.available_locales | own_locales).map(&:to_sym)
        end

        def controller
          defined?(::ApplicationController) ? ::ApplicationController : ActionController::Base
        end

        def view_paths
          controller.view_paths
        end

        def app_prefixes
          controller._prefixes
        end
      end

      # The locals a live partial declares with Rails' strict-locals comment.
      # Without the comment it takes none.
      class Signature
        # @return [Array<Symbol>]
        attr_reader :required

        # @return [Hash{Symbol=>String}] Each optional local's default, as Ruby
        attr_reader :optional

        # @return [Symbol, nil] :** for an anonymous **, or the name of a **rest
        attr_reader :rest

        # @return [String, nil] As written in the comment
        attr_reader :source

        def self.parse(source, file)
          match = source.match(ActionView::Template::STRICT_LOCALS_REGEX)
          return new unless match

          code = match[1].rstrip
          return new(source: code) if code.blank? || code == '**nil'

          result = Prism.parse("def __lc_locals(#{code}); end")
          unless result.success?
            raise CompileError, "#{file}: its strict-locals comment doesn't parse: locals: (#{code})"
          end

          new(source: code, parameters: result.value.statements.body.first.parameters, file:)
        end

        def initialize(source: nil, parameters: nil, file: nil)
          @source = source
          @required = []
          @optional = {}
          @rest = nil
          read(parameters, file) if parameters
        end

        def declared?
          !source.nil?
        end

        # @return [Array<Symbol>] Every named local
        def names
          required + optional.keys + (rest && rest != :** ? [rest] : [])
        end

        def accepts?(key)
          !rest.nil? || required.include?(key) || optional.key?(key)
        end

        # Block parameters only take primary expressions as defaults, so each
        # one is parenthesised.
        #
        # @return [String]
        def block_parameters
          params = required.map { |name| "#{name}:" }
          params.concat(optional.map { |name, default| "#{name}: (#{default}\n)" })
          params << (rest == :** ? '**' : "**#{rest}") if rest
          params.join(', ')
        end

        private

        def read(parameters, file)
          if parameters.requireds.any? || parameters.optionals.any? || parameters.rest || parameters.posts.any? ||
             parameters.block
            raise CompileError, "#{file}: locals: (#{source}) declares positional or block arguments; " \
                                'strict locals can only be keywords'
          end

          parameters.keywords.each do |keyword|
            if keyword.is_a?(Prism::OptionalKeywordParameterNode)
              @optional[keyword.name] = keyword.value.slice
            else
              @required << keyword.name
            end
          end

          rest = parameters.keyword_rest
          @rest = rest.name || :** if rest.is_a?(Prism::KeywordRestParameterNode)
        end
      end

      # A live partial's file, parsed and checked once per compile.
      class PartialFile
        # @return [ActionView::Template]
        attr_reader :template

        # @return [Herb::AST::DocumentNode]
        attr_reader :ast

        # @return [Signature]
        attr_reader :signature

        # @return [Array<Symbol>] Locals the partial assigns at its top level
        attr_reader :own_locals

        # @return [String] The partial's Ruby, at the same offsets as in the file
        attr_reader :ruby

        def initialize(template)
          @template = template
          source = template.encode!
          @signature = Signature.parse(source, identifier)
          @ast = parse(source)
          analyze
        end

        def identifier
          template.short_identifier
        end

        def virtual_path
          template.virtual_path
        end

        # @return [String] The local a partial binds object: or a collection item to
        def default_as
          File.basename(virtual_path).delete_prefix('_').to_sym
        end

        # The line of the first place the partial uses a name.
        def line_of(name)
          index = ruby =~ /(?<![\w@$.])#{Regexp.escape(name.to_s)}\b/
          index && (ruby[0...index].count("\n") + 1)
        end

        private

        def parse(source)
          result = ::Herb.parse(source, track_whitespace: true)
          error = result.errors.find { |candidate| STRUCTURAL_ERRORS.any? { |type| candidate.is_a?(type) } }

          if error
            raise CompileError, "#{identifier}:#{error.location.start.line}: #{error.message} " \
                                'A live partial is compiled on its own, so it must be complete.'
          end

          @ruby = without_comments(::Herb.extract_ruby(source), result.value)
          result.value
        end

        # Herb joins tags with `;`, which a comment at the end of a tag would
        # swallow. Its output keeps each byte where the source had it.
        def without_comments(ruby, node)
          ruby = ruby.b
          each_tag(node) do |tag|
            Prism.parse(tag.content.value).comments.each do |comment|
              ruby[tag.content.range.from + comment.location.start_offset, comment.location.length] =
                ' ' * comment.location.length
            end
          end
          ruby.force_encoding(Encoding::UTF_8)
        end

        def each_tag(node, &)
          yield node if node.respond_to?(:tag_opening) && node.respond_to?(:content) && node.content.is_a?(Herb::Token)
          node.child_nodes.compact.each { |child| each_tag(child, &) }
        end

        def analyze
          parsed = Prism.parse(ruby, scopes: [signature.names | [:local_assigns]])
          unless parsed.success?
            error = parsed.errors.first
            raise CompileError, "#{identifier}:#{error.location.start_line}: #{error.message}"
          end

          visitor = DependencyVisitor.new
          visitor.visit(parsed.value)
          @own_locals = visitor.local_writes - signature.names - [:local_assigns]

          ConstructCheck.new(self).visit(parsed.value)
        end
      end

      # Constructs that would mean something else once inlined.
      class ConstructCheck < Prism::Visitor
        def initialize(file)
          super()
          @file = file
          @first_writes = {}
          @reads = []
          @nested = 0
        end

        def visit_program_node(node)
          super
          check_reads_before_writes
        end

        def visit_yield_node(node)
          error!(node, "can't yield: it is inlined into the template that renders it, which has no block to give")
        end

        def visit_return_node(node)
          if @nested.zero?
            error!(node, "can't `return`: inlined, it would end the template part that renders it. " \
                         'Wrap the content in if/unless instead')
          end

          super
        end

        def visit_def_node(node) = nested { super }

        def visit_lambda_node(node) = nested { super }

        %i[read write operator_write and_write or_write target].each do |kind|
          define_method(:"visit_instance_variable_#{kind}_node") do |node|
            next if node.name == :@output_buffer

            error!(node, "uses #{node.name}: part code runs on LiveCable's renderer, not the view, so instance " \
                         'variables are not the ones the page set. Pass the value as a local')
          end
        end

        def visit_call_node(node)
          if node.receiver.nil? && node.name == :cache && node.block
            error!(node, "can't use `cache`: its fragments are keyed by the component template's digest, " \
                         'which an edit to the partial does not change')
          end

          @reads << node if node.variable_call? && @file.own_locals.include?(node.name)

          super
        end

        %i[write operator_write and_write or_write target].each do |kind|
          define_method(:"visit_local_variable_#{kind}_node") do |node|
            @first_writes[node.name] ||= node.location.start_offset
            super(node)
          end
        end

        private

        def nested
          @nested += 1
          yield
        ensure
          @nested -= 1
        end

        # A name read before the partial assigns it is a method call in a plain
        # partial, but a nil local once the partial's locals are declared.
        def check_reads_before_writes
          @reads.each do |read|
            write = @first_writes[read.name]
            next unless write && read.location.start_offset < write

            error!(read, "reads `#{read.name}` before assigning it; use `self.#{read.name}` for the " \
                         "component's value, or rename the local")
          end
        end

        def error!(node, message)
          raise CompileError, "#{@file.identifier}:#{node.location.start_line} #{message}"
        end
      end

      # One render of a live partial: what it passes, and the Ruby that wraps
      # the partial's code.
      class Site
        # @return [PartialFile]
        attr_reader :file

        # @return [Symbol, nil] The local a collection item is bound to
        attr_reader :as

        # @return [String, nil]
        attr_reader :collection

        def initialize(file, call, inliner)
          @file = file
          @call = call
          @inliner = inliner
          @locals = {}
          @collection = nil
          @as = nil
          read_arguments
          check_locals!
        end

        def collection?
          !collection.nil?
        end

        # @return [String] Ruby
        def opening
          params = ['local_assigns', file.signature.block_parameters].reject(&:empty?).join(', ')
          own = file.own_locals.join(', ')
          bars = own.empty? ? "|#{params}|" : "|#{params}; #{own}|"
          path = file.virtual_path.inspect

          if collection?
            arguments = [path, "(#{collection}\n)", as.inspect, locals_hash, implicit_locals.inspect]
            "#{COLLECTION}(#{arguments.join(', ')}) do #{bars}"
          else
            "#{PARTIAL}(#{path}, #{locals_hash}) do #{bars}"
          end
        end

        def closing
          'end'
        end

        private

        def read_arguments
          @inliner.error!("render '#{target}' can't take a block when it renders a live partial") if @call.block

          arguments = @call.arguments&.arguments || []
          first = arguments.first

          if first.is_a?(Prism::StringNode)
            @inliner.error!("render '#{target}' has too many arguments") if arguments.size > 2
            read_locals(arguments[1])
          else
            read_options(first)
          end
        end

        def read_options(options)
          options = hash_entries(options)
          unsupported = options.keys - OPTIONS
          if unsupported.any?
            @inliner.error!(
              "#{file.identifier} can't be rendered with #{unsupported.map { |key| "#{key}:" }.join(', ')} " \
              '(live partials support locals:, object:, as: and collection:)'
            )
          end

          read_locals(options[:locals])
          @as = read_as(options[:as]) || file.default_as

          if options[:object] && options[:collection]
            @inliner.error!("render '#{target}' passes both object: and collection:")
          elsif options[:collection]
            @collection = options[:collection].slice
          elsif options[:object]
            @locals[@as] = options[:object].slice
          end
        end

        def read_locals(node)
          return if node.nil?

          unless node.is_a?(Prism::KeywordHashNode) || node.is_a?(Prism::HashNode)
            @inliner.error!("render '#{target}' passes its locals as #{node.slice}; a live partial's locals must " \
                            'be a literal Hash with Symbol keys, known when the template compiles')
          end

          node.elements.each do |element|
            unless element.is_a?(Prism::AssocNode) && element.key.is_a?(Prism::SymbolNode)
              @inliner.error!("render '#{target}' passes #{element.slice}; a live partial's locals must have " \
                              'literal Symbol keys, known when the template compiles')
            end

            key = element.key.unescaped.to_sym
            @locals[key] = element.value.is_a?(Prism::ImplicitNode) ? key.to_s : element.value.slice
          end
        end

        def read_as(node)
          return if node.nil?

          name = node.unescaped if node.is_a?(Prism::SymbolNode)
          @inliner.error!("render '#{target}' needs a Symbol literal for as:") unless name&.match?(LOCAL_NAME)

          name.to_sym
        end

        def hash_entries(node)
          unless node.is_a?(Prism::KeywordHashNode) || node.is_a?(Prism::HashNode)
            @inliner.error!("can't read the arguments of #{@call.slice}")
          end

          node.elements.to_h do |element|
            unless element.is_a?(Prism::AssocNode) && element.key.is_a?(Prism::SymbolNode)
              @inliner.error!("render passes #{element.slice}; the options of a live partial's render must be " \
                              'known when the template compiles')
            end

            [element.key.unescaped.to_sym, element.value]
          end
        end

        def check_locals!
          signature = file.signature
          keys = passed_keys

          unless signature.declared?
            return if keys.empty?

            passed = keys.map { |key| "#{key}:" }.join(', ')
            @inliner.error!(
              "passes #{passed} to #{file.identifier}, which declares no locals. Live partials need a " \
              "strict-locals comment: add <%# locals: (#{passed}) -%> as its first line"
            )
          end

          missing = signature.required - keys
          unknown = keys.reject { |key| signature.accepts?(key) }
          return if missing.empty? && unknown.empty?

          problems = []
          problems << "is missing #{missing.join(', ')}" if missing.any?
          problems << "passes unknown #{unknown.map { |key| "#{key}:" }.join(', ')}" if unknown.any?

          @inliner.error!("render '#{target}' #{problems.join(' and ')} " \
                          "(#{file.identifier} declares locals: (#{signature.source}))")
        end

        def passed_keys
          keys = @locals.keys
          keys.push(as, *implicit_locals) if collection?
          keys
        end

        # The counter and iteration Rails passes a collection's items, which
        # it drops when the partial's strict locals don't name them.
        def implicit_locals
          implicit = %I[#{as}_counter #{as}_iteration]
          file.signature.rest ? implicit : implicit & file.signature.names
        end

        def locals_hash
          entries = @locals.map do |key, value|
            name = key.to_s.match?(LOCAL_NAME) ? "#{key}:" : "#{key.inspect} =>"
            "#{name} (#{value}\n)"
          end

          "{ #{entries.join(', ')} }"
        end

        def target
          LivePartials.render_path(file.virtual_path)
        end
      end

      # Finds the renders of live partials in one file's tags. The compiler
      # keeps one per file it compiles, the component template first and then
      # each partial it inlines.
      class Inliner
        # @return [String]
        attr_reader :identifier

        # @return [Hash{String=>PartialFile}] Every partial inlined, by virtual path
        attr_reader :files

        # @param template [ActionView::Template] The component template
        def self.for(template)
          new(Resolver.new(template), identifier: template.short_identifier, virtual_path: template.virtual_path)
        end

        def initialize(resolver, identifier:, virtual_path:, stack: [], files: {}, cache: {})
          @resolver = resolver
          @identifier = identifier
          @virtual_path = virtual_path
          @stack = stack
          @files = files
          @cache = cache
          @line = nil
        end

        # @return [Inliner] The inliner for a partial this file renders
        def nested(file)
          self.class.new(@resolver, identifier: file.identifier, virtual_path: file.virtual_path,
            stack: @stack + [@identifier], files: @files, cache: @cache)
        end

        # The render a <%= %> tag inlines, or nil when it renders no live partial.
        #
        # @param node [Herb::AST::ERBContentNode]
        # @return [Site, nil]
        def site_for(node)
          code = node.content&.value
          return if node.tag_opening.value.start_with?('<%#') || !code&.include?('render')

          @line = node.location.start.line
          sole = sole_render(code) if node.tag_opening.value.start_with?('<%=')

          render_calls(code).each do |call|
            file = resolve(call) or next
            misuse!(call, code, file) unless call.equal?(sole)

            return Site.new(file, call, self)
          end

          nil
        end

        # Raises for a live partial rendered from any tag other than a
        # <%= render ... %> of its own.
        #
        # @param node [Herb::AST::Node] A tag with Ruby in it
        def check!(node)
          code = node.content&.value
          return unless code&.include?('render')

          @line = node.location.start.line
          render_calls(code).each do |call|
            file = resolve(call) or next
            misuse!(call, code, file)
          end
        end

        def error!(message)
          raise CompileError, "#{@identifier}#{":#{@line}" if @line}: #{message}"
        end

        private

        def resolve(call)
          path, option = literal_target(call)
          return unless path

          template = if path.include?('/')
                       @resolver.resolve(path, self)
                     else
                       @resolver.check_bare_name!(path, @virtual_path, self)
                     end
          return unless template

          if option == :layout
            error!("#{template.short_identifier} can't be rendered with layout: " \
                   '(live partials support locals:, object:, as: and collection:)')
          end

          file = (@cache[template.identifier] ||= PartialFile.new(template))
          check_recursion!(file)
          @files[file.virtual_path] = file
        end

        def check_recursion!(file)
          chain = @stack + [@identifier]
          return unless chain.include?(file.identifier)

          names = (chain.drop_while { |name| name != file.identifier } + [file.identifier]).map do |name|
            name.sub(%r{\.[^/]*\z}, '').sub(%r{\Aapp/views/}, '')
          end

          raise CompileError, "#{file.identifier} renders itself (#{names.join(' -> ')}). Live partials are inlined " \
                              "at compile time and can't recurse: use a child component, or a .html.erb partial " \
                              'with locals'
        end

        def misuse!(call, code, file)
          target = LivePartials.render_path(file.virtual_path)
          error!("render '#{target}' isn't the whole of an output tag, so it can't inline a live partial " \
                 "(#{file.identifier}). #{rewrite(call, code, target)}")
        end

        def rewrite(call, code, target)
          if call.block
            return 'Live partials take no block: pass what the block renders as a local, or use a .html.erb partial'
          end

          statement = sole_statement(code)
          if (statement.is_a?(Prism::IfNode) || statement.is_a?(Prism::UnlessNode)) &&
             statement.statements&.body&.first.equal?(call)
            keyword = statement.is_a?(Prism::IfNode) ? 'if' : 'unless'
            return "Write <% #{keyword} #{statement.predicate.slice} %><%= #{call.slice} %><% end %>"
          end

          "Write it as its own tag, <%= render '#{target}', ... %>, inside <% if %> or <% unless %> if it " \
            'is conditional'
        end

        def literal_target(call)
          first = call.arguments&.arguments&.first

          case first
          when Prism::StringNode then [first.unescaped, nil]
          when Prism::KeywordHashNode, Prism::HashNode
            %i[partial layout].each do |key|
              element = first.elements.find do |candidate|
                candidate.is_a?(Prism::AssocNode) && candidate.key.is_a?(Prism::SymbolNode) &&
                  candidate.key.unescaped == key.to_s
              end

              return [element.value.unescaped, key] if element&.value.is_a?(Prism::StringNode)
            end

            nil
          end
        end

        def sole_statement(code)
          body = parse(code)&.statements&.body
          body.first if body&.one?
        end

        def sole_render(code)
          call = sole_statement(code)
          call if call.is_a?(Prism::CallNode) && call.name == :render && call.receiver.nil?
        end

        def render_calls(code)
          collector = RenderCollector.new
          parse(code)&.accept(collector)
          collector.calls
        end

        # A block's opening tag doesn't parse on its own, so it is closed first.
        def parse(code)
          @parses ||= {}
          @parses.fetch(code) do
            result = ['', "\nend", "\n}"].lazy.map { |closer| Prism.parse("#{code}#{closer}") }.find(&:success?)
            @parses[code] = result&.value
          end
        end
      end

      class RenderCollector < Prism::Visitor
        attr_reader :calls

        def initialize
          super
          @calls = []
        end

        def visit_call_node(node)
          @calls << node if node.name == :render && node.receiver.nil?
          super
        end
      end

      # Raises when a live partial's code reaches a local of the file that
      # renders it, which a plain partial could never see: the copied code is a
      # block, and a block sees its caller's locals.
      class ScopeCheck < Prism::Visitor
        # @param files [Hash{String=>PartialFile}]
        # @param identifier [String] The component template
        def initialize(files, identifier)
          super()
          @files = files
          @identifier = identifier
          @depth = 0
          @barriers = []
        end

        def visit_call_node(node)
          return super unless wrapper?(node)

          visit(node.arguments)
          @barriers.push([@depth + 1, node.arguments.arguments.first.unescaped])
          visit(node.block)
        ensure
          @barriers.pop if wrapper?(node)
        end

        def visit_block_node(node) = nested { super }

        def visit_lambda_node(node) = nested { super }

        def visit_def_node(node) = nested { super }

        %i[read write operator_write and_write or_write target].each do |kind|
          define_method(:"visit_local_variable_#{kind}_node") do |node|
            check(node, kind)
            super(node)
          end
        end

        private

        def wrapper?(node)
          node.receiver.nil? && WRAPPERS.include?(node.name) && node.block.is_a?(Prism::BlockNode) &&
            node.arguments&.arguments&.first.is_a?(Prism::StringNode)
        end

        def nested
          @depth += 1
          yield
        ensure
          @depth -= 1
        end

        def check(node, kind)
          return if @barriers.empty? || node.name.start_with?('__lc_')

          barrier, virtual_path = @barriers.last
          return if @depth - node.depth >= barrier

          file = @files[virtual_path]
          caller = @barriers[-2] ? @files[@barriers[-2][1]]&.identifier : @identifier
          location = [file&.identifier || virtual_path, file&.line_of(node.name)].compact.join(':')

          if kind == :read
            raise CompileError, "#{location} reads `#{node.name}`, a local of the template that renders it " \
                                "(#{caller}). Pass it as a local, or rename one of them."
          end

          raise CompileError, "#{location} assigns `#{node.name}` inside a block, and `#{node.name}` is a local " \
                              "of the template that renders it (#{caller}). Rename one of them."
        end
      end
    end
  end
end
