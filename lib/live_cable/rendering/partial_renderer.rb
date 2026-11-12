# frozen_string_literal: true

require 'action_view/renderer/collection_renderer'

module LiveCable
  module Rendering
    # Base class for partial renderers with common functionality
    class PartialRenderer
      # @return [LiveCable::Component]
      attr_reader :component

      # @param render_context [LiveCable::RenderContext, nil] The component's,
      #   for its collection streams
      def initialize(component, parts, view_context, virtual_path = nil, template = nil, render_context: nil)
        @component = component
        @parts = parts
        @view_context = view_context
        @virtual_path = virtual_path
        @template = template
        @render_context = render_context
        bind_shadowed_names
      end

      def render_changes(changes = :all)
        # Nothing changed: one nil per part the view gets, which leaves out :code parts
        return Array.new(@parts.count { |part| part[0] != :code }) if changes == []

        @full_render = %i[all dynamic].include?(changes)
        @locals = {}
        @dirty_locals = Set.new  # Track which locals were recomputed this render
        @method_deps_cache = {}  # Cache method dependency expansion for this render cycle
        within_template do
          @parts.each_with_index.with_object([]) do |item, acc|
            part, index = item
            result = @view_context.render_part(index) { __send__("render_part_#{index}", changes) }
            acc << result unless part[0] == :code
          end
        end
      end

      # The update for each stream the client holds that has queued ops or a
      # reset, which takes its queue. Runs no part code.
      #
      # @yieldparam stream [Streams::Stream]
      # @yieldreturn [Boolean] whether the client holds the stream
      # @return [Array<Array(Streams::Stream, Hash)>] A whole node after a
      #   reset, otherwise an {"o" => ops} diff
      def render_held_streams
        self.class.streams.each_value.filter_map do |meta|
          stream = component.live_stream(meta.name)
          next unless (stream.ops? || stream.reset?) && yield(meta)

          update = within_template do
            stream.reset? ? full_stream(stream, meta, fold: true) : { 'o' => render_stream_ops(stream, meta) }
          end

          [meta, update]
        end
      end

      # Pass through renders to the view context, otherwise method_missing will pass
      # to the component instead since it also has a render method
      def render(...)
        @view_context.render(...)
      end

      def mark_locals_dirty(locals)
        locals.each { |local| @dirty_locals << local }
      end

      # Expand component.method_name calls to their transitive dependencies
      # Results are cached per render cycle to avoid redundant analysis
      # @param method_names [Array<Symbol>] Method names called on component
      # @return [Array<Symbol>] Reactive variables these methods depend on
      def expand_component_method_dependencies(method_names)
        return [] if method_names.empty?

        # Use cache key based on the sorted method names array
        cache_key = method_names.sort

        # Return cached result if available
        return @method_deps_cache[cache_key] if @method_deps_cache.key?(cache_key)

        # Get the analyzer for the component class
        analyzer = component.class.method_dependencies_analyzer

        expanded = []
        method_names.each do |method_name|
          # Get transitive dependencies for this method
          deps = analyzer.expanded_dependencies(method_name)
          expanded.concat(deps.to_a)
        end

        # Cache and return the result
        @method_deps_cache[cache_key] = expanded.uniq
      end

      # Check if this part should be skipped based on its dependencies
      # @param changes [Symbol|Array] Changed variables, :all, or :dynamic
      # @param component_dependencies [Array<Symbol>] Direct component dependencies
      # @param component_method_calls [Array<Symbol>] Component methods called
      # @param local_dependencies [Array<Symbol>] Local variable dependencies
      # @return [Boolean] true if the part should be skipped
      def should_skip_part?(changes, component_dependencies, component_method_calls, local_dependencies)
        # Always render on initial render (all parts)
        return false if changes == :all

        # Always render on template switch (all dynamic parts must render)
        return false if changes == :dynamic

        return false if component_method_calls.any? && !component.class.method_dependencies_analyzer.analyzable?

        # Expand component.method_name calls to their transitive dependencies
        expanded_deps = expand_component_method_dependencies(component_method_calls)
        all_component_deps = component_dependencies | expanded_deps

        # Render if any component dependencies changed
        return false if changes.intersect?(all_component_deps)

        # Render if any local dependencies are dirty
        return false if @dirty_locals.intersect?(local_dependencies)

        # Otherwise, skip rendering this part
        true
      end

      def method_missing(method, ...)
        if component.respond_to?(method)
          return call_component(method, ...)
        end

        if @view_context.respond_to?(method)
          return @view_context.public_send(method, ...)
        end

        super
      end

      def respond_to_missing?(method, _include_private = false)
        component.respond_to?(method) || @view_context.respond_to?(method)
      end

      private

      def with_buffer(&)
        @output_buffer = ViewBuffer.new(@view_context)

        @view_context.with_output_buffer(ActionView::OutputBuffer.new, &).to_s
      end

      # Runs a tree part's code and returns the node it builds. The code
      # writes nothing to the buffer itself; the buffer is only there so a
      # helper that writes to it (concat, safe_concat) cannot reach the
      # template's own output.
      def render_tree
        node = nil
        stray = with_buffer { node = yield }

        unless stray.empty?
          LiveCable.warn_once(
            "[LiveCable] #{component.class.name} wrote to the output buffer from a non-output tag inside " \
            'a control block; that output is dropped. Use an output tag (<%= %>) instead.'
          )
        end

        node
      end

      # A value inside a tree part, escaped the way <%= %> would escape it.
      def __lc_esc(value)
        return '' if value.nil?

        value = value.to_s
        value.html_safe? ? String.new(value) : ERB::Util.unwrapped_html_escape(value)
      end

      # A value inside a tree part, as <%== %> would write it.
      def __lc_raw(value)
        value.nil? ? '' : String.new(value.to_s)
      end

      # A construct inside a tree part that is kept as one HTML value.
      def __lc_capture(&)
        String.new(with_buffer(&))
      end

      def within_template(&)
        @view_context.with_live_cable_virtual_path(@virtual_path) do
          @view_context.with_current_template(@template, &)
        end
      end

      # A collection stream's node (see Streams): its rows from the initial
      # lambda, unless the client holds it and this render doesn't start the
      # template afresh, which leaves it as it is.
      def __lc_stream(name, _scope)
        stream = component.live_stream(name)
        meta = self.class.streams.fetch(name)
        return full_stream(stream, meta, fold: false) unless component.live_connection

        if @full_render || !component.stream_held?(name)
          full_stream(stream, meta, fold: @render_context.delivering?)
        else
          Tree::StreamPlaceholder.for(name, meta.scope)
        end
      end

      # A render that reaches the client takes the queue and folds it in, so
      # ops queued since a reset or before the first render arrive in the node
      def full_stream(stream, meta, fold:)
        rows = {}

        stream.initial_items.each do |item|
          key = stream.key_for(item)
          rows[key] = render_stream_row(stream, meta, item, key)
        end

        node = Tree::StreamNode.build(stream.name, meta.scope, rows, stream.limit, key_id: meta.key_id)
        fold ? Tree::StreamNode[Tree.apply_ops(node, render_stream_ops(stream, meta))] : node
      end

      def render_stream_ops(stream, meta)
        stream.take.map do |type, key, row|
          type == 'd' ? [type, key] : [type, key, render_stream_row(stream, meta, row, key)]
        end
      end

      def render_stream_row(stream, meta, item, key)
        @render_context&.rendering_stream_row = stream.name

        @view_context.with_live_cable_virtual_path(meta.virtual_path) do
          verify_row_id(stream, meta, item, key) if meta.user_id_code && LiveCable.configuration.verify_stream_items
          render_tree { __send__(meta.row_method, item, key) }
        end
      ensure
        @render_context&.rendering_stream_row = nil
      end

      def verify_row_id(stream, meta, item, key)
        id = __send__(meta.id_method, item)
        return if id == key

        raise LiveCable::Error, "stream :#{stream.name}: the row's id `#{id}` isn't its dom id `#{key}`. Remove the " \
                                "id attribute, or declare #{stream.dom_id_example} returning `#{id}`"
      end

      # An inlined live partial (see LivePartials). Its block takes
      # local_assigns and the locals as keywords.
      def __lc_partial(virtual_path, locals)
        @view_context.with_live_cable_virtual_path(virtual_path) { yield(locals, **locals) }
      end

      def __lc_partial_collection(virtual_path, collection, as, locals, implicit)
        items = collection.respond_to?(:to_ary) ? collection.to_ary : Array(collection)
        iteration = ActionView::PartialIteration.new(items.size)

        items.each do |item|
          assigns = locals.merge(as => item)
          assigns[:"#{as}_counter"] = iteration.index if implicit.include?(:"#{as}_counter")
          assigns[:"#{as}_iteration"] = iteration if implicit.include?(:"#{as}_iteration")

          @view_context.with_live_cable_virtual_path(virtual_path) { yield(assigns, **assigns) }
          iteration.iterate!
        end

        nil
      end

      def store_local(name, value)
        @locals[name] = value
      end

      def call_component(name, ...)
        @view_context.live_cable_unwrap(component.public_send(name, ...))
      end

      # Kernel and Object names never reach method_missing. Bind the ones the component
      # or view context define themselves; a wrapper falling back to Kernel breaks lambda.
      def bind_shadowed_names
        names = self.class.metadata.compact.flat_map { |part| part[:component_method_calls] || [] }
        names = (names + self.class.row_method_calls).uniq
        names = names.select { |name| Object.method_defined?(name) || Object.private_method_defined?(name) }

        # The renderer's respond_to? already checks the component and the view context.
        (names - [:respond_to?]).each do |name|
          target = [component, @view_context].find do |object|
            if Object.private_method_defined?(name)
              object.respond_to?(name)
            else
              object.class.public_method_defined?(name) &&
                object.class.instance_method(name).owner != Object.instance_method(name).owner
            end
          end
          next unless target

          define_singleton_method(name) do |*args, **kwargs, &block|
            next call_component(name, *args, **kwargs, &block) if target.equal?(component)

            target.public_send(name, *args, **kwargs, &block)
          end
        end
      end
    end
  end
end
