# frozen_string_literal: true

module LiveCable
  class Component
    module CollectionStreams
      extend ActiveSupport::Concern

      # For dom_id: lambdas. Private, so templates still call the view's.
      module RecordIdentifier
        private

        def dom_id(...) = ActionView::RecordIdentifier.dom_id(...)

        def dom_class(...) = ActionView::RecordIdentifier.dom_class(...)
      end

      included do
        class_attribute :collection_streams, default: {}.freeze, instance_accessor: false, instance_predicate: false
      end

      class_methods do
        # @param name [Symbol]
        # @param initial [Proc, nil] the rows of a full render
        # @param dom_id [Proc, nil] a row's key, run on the component
        # @param limit [Integer, nil] the most rows the client keeps
        def stream(name, initial = nil, dom_id: nil, limit: nil)
          check_stream_declaration(name, initial, dom_id, limit)
          declaration = LiveCable::Stream::Declaration.new(name, initial, dom_id, limit)

          include RecordIdentifier

          define_method(name) do
            raise LiveCable::Error,
              "`#{self.class.name}##{name}` is a collection stream: it holds no rows, so it can't be read or " \
              "enumerated. Render it with `<%= live_stream_for :#{name} do |#{declaration.row_name}| %>`, and " \
              'change it with `stream_insert`, `stream_update`, `stream_delete` or `stream_reset`'
          end

          self.collection_streams = collection_streams.merge(name => declaration).freeze
        end

        def reactive(variable, ...)
          check_not_stream(variable, "declare reactive :#{variable}")
          super
        end

        def shared(variable, ...)
          check_not_stream(variable, "declare shared :#{variable}")
          super
        end

        def reactive_query(name, ...)
          check_not_stream(name, "declare reactive_query :#{name}")
          super
        end

        def method_added(name)
          super
          check_not_stream(name, "define ##{name}")
        end

        def check_not_stream(name, what)
          return unless collection_streams.key?(name)

          raise ArgumentError, "#{self.name} can't #{what}: it is already a collection stream"
        end

        def check_stream_declaration(name, initial, dom_id, limit)
          problem =
            if !name.is_a?(Symbol) || !name.match?(LiveCable::Rendering::Streams::NAME)
              "a stream's name is a Symbol of lowercase letters, digits and underscores that starts with a " \
                'letter or an underscore'
            elsif !initial.nil? && !initial.is_a?(Proc)
              "its initial value must be a proc or nil, got #{initial.inspect}"
            elsif !dom_id.nil? && !dom_id.is_a?(Proc)
              "dom_id: must be a proc, got #{dom_id.inspect}"
            elsif !limit.nil? && !(limit.is_a?(Integer) && limit.positive?)
              "limit: must be a positive Integer or nil, got #{limit.inspect}"
            else
              stream_name_taken(name)
            end

          raise ArgumentError, "#{self.name} can't declare stream #{name.inspect}: #{problem}" if problem
        end

        def stream_name_taken(name)
          if collection_streams.key?(name)
            'it is already declared'
          elsif reactive_variables.include?(name) || shared_reactive_variables.include?(name)
            'it is already a reactive variable'
          elsif shared_variables.include?(name)
            'it is already a shared variable'
          elsif reactive_queries.key?(name)
            'it is already a reactive_query'
          elsif method_defined?(name) || (private_method_defined?(name) && !global_method?(name))
            "it is already a method (#{instance_method(name).owner.name}##{name})"
          end
        end

        # Kernel's private methods, such as format and select, which every object has
        def global_method?(name)
          Object.ancestors.include?(instance_method(name).owner)
        end

        private :method_added, :check_not_stream, :check_stream_declaration, :stream_name_taken, :global_method?
      end

      # Queue a row's insert for the next render that reaches the client. A
      # key the client already holds is replaced where it is.
      #
      # @param at [Symbol] :end or :start
      def stream_insert(name, row, at: :end)
        changing_stream(name, __method__).insert(row, at:)
      end

      # Queue a row's update, which a client that doesn't hold its key ignores
      def stream_update(name, row)
        changing_stream(name, __method__).update(row)
      end

      # @param row_or_key [Object, String] a String is the row's key
      def stream_delete(name, row_or_key)
        changing_stream(name, __method__).delete(row_or_key)
      end

      # Drop the queued ops and refill the stream from its initial lambda on
      # the next render that reaches the client, followed by later ops
      def stream_reset(name)
        changing_stream(name, __method__).reset
      end

      # Run the block holding the connection's lock, then send what changed.
      # Inside an action, a callback or another lock holder it only runs the
      # block.
      #
      # @return [Object] the block's value
      def live_update
        connection = live_connection || raise(no_connection(__method__))

        if connection.synchronized?
          check_not_rendering(connection, __method__)
          return yield
        end

        connection.synchronize do
          raise no_connection(__method__) unless live_connection.equal?(connection)

          result = yield
          connection.broadcast_changeset
          result
        end
      end

      # @api private
      # @return [LiveCable::Stream]
      def live_stream(name)
        declaration = self.class.collection_streams.fetch(name) do
          declared = self.class.collection_streams.keys.map(&:inspect).join(', ').presence || 'none'
          raise LiveCable::Error, "#{self.class.name} has no stream #{name.inspect} (declared: #{declared})"
        end

        (@live_streams ||= {})[name] ||= LiveCable::Stream.new(declaration, self)
      end

      # @api private
      # @return [Array(String, LiveCable::Rendering::Streams::Stream), nil]
      #   The last rendered template and where it puts the stream, if it has it
      def rendered_stream(name)
        stream = @live_template&.streams&.[](name)
        [previous_template_path, stream] if stream
      end

      # @api private
      # @return [Boolean] whether the client holds the stream where the last
      #   rendered template puts it
      def stream_held?(name)
        stream = @live_template&.streams&.[](name)
        !stream.nil? && tree_tracker.held_stream?(previous_template_path, @live_template.statics, stream)
      end

      # @api private
      # @return [Boolean] whether a stream the client holds has ops or a reset
      #   to send. One it doesn't hold sends them with its next full render.
      def streams_pending?
        return false unless @live_streams

        @live_streams.any? { |name, stream| (stream.ops? || stream.reset?) && stream_held?(name) }
      end

      # @api private
      # Drops what's queued for streams the client doesn't hold, which only a
      # render that shows them again would have sent. Before the client holds
      # anything for the template, the next render is a full one and sends it.
      def discard_absent_stream_ops
        return unless @live_streams && @live_template
        return unless tree_tracker.known?(previous_template_path, @live_template.statics)

        @live_streams.each { |name, stream| stream.discard unless stream_held?(name) }
      end

      # @api private
      # @return [String, nil] why no render sends queued ops this cycle
      def stream_ops_waiting
        if !subscribed?
          "before #{self.class.name} subscribed"
        elsif render_halted
          "while a render callback halted #{self.class.name}'s renders"
        end
      end

      # @api private
      def discard_stream_ops
        @live_streams&.each_value(&:discard)
      end

      private

      def changing_stream(name, verb)
        stream = live_stream(name)
        connection = live_connection || raise(no_connection(verb))

        unless connection.synchronized?
          raise LiveCable::Error, "#{self.class.name}##{verb} was called outside the connection lock: " \
                                  'wrap it in `live_update { … }`'
        end

        check_not_rendering(connection, verb)
        stream
      end

      def no_connection(verb)
        LiveCable::Error.new(
          "#{self.class.name}##{verb} needs a live connection: call it from an action, a `stream_from` " \
          "callback or `after_connect`; for the first page, return the rows from the stream's initial lambda"
        )
      end

      def check_not_rendering(connection, verb)
        return unless connection.rendering?

        raise LiveCable::Error, "#{self.class.name}##{verb} was called while rendering: queue stream changes " \
                                'in the action or callback'
      end
    end
  end
end
