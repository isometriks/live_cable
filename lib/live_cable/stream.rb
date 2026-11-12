# frozen_string_literal: true

module LiveCable
  # One component's collection stream: the row ops queued for the next render
  # that reaches the client, and whether that render must refill the stream
  # from its initial lambda. It never keeps rows between renders.
  class Stream
    MAX_PENDING = 1_000
    POSITIONS = { end: 'a', start: 'p' }.freeze

    # What `stream` declares on the component class
    Declaration = Data.define(:name, :initial, :dom_id, :limit) do
      # @return [String] what a row is called in messages
      def row_name
        singular = name.to_s.singularize
        singular == name.to_s ? 'row' : singular
      end
    end

    # @return [Array<Array>] [type, key, row] per op, oldest first; a delete
    #   carries no row
    attr_reader :ops

    # @param declaration [Declaration]
    # @param component [LiveCable::Component]
    def initialize(declaration, component)
      @declaration = declaration
      @component = component
      discard
    end

    # @return [Symbol]
    def name = @declaration.name

    # @return [Integer, nil]
    def limit = @declaration.limit

    def insert(row, at: :end)
      type = POSITIONS.fetch(at) { raise ArgumentError, "at: must be :end or :start, got #{at.inspect}" }
      push([type, key_for(row), row])
    end

    def update(row)
      push(['u', key_for(row), row])
    end

    def delete(row_or_key)
      push(['d', row_or_key.is_a?(String) ? check_key(row_or_key) : key_for(row_or_key)])
    end

    def reset
      @ops = []
      @reset = true
      @collapsed = false
      nil
    end

    def ops? = @ops.any?

    # @return [Boolean] whether the next delivering render refills the stream
    def reset? = @reset

    # @return [Boolean] whether the queue overflowed into a refill
    def collapsed? = @collapsed

    # @return [Array<Array>] the queued ops, leaving the stream empty
    def take
      ops = @ops
      discard
      ops
    end

    def discard
      @ops = []
      @reset = @collapsed = false
      nil
    end

    # @return [Array] the initial lambda's rows
    def initial_items
      initial = @declaration.initial
      return [] unless initial

      (initial.arity.zero? ? initial.call : initial.call(@component)).to_a
    end

    # @return [String] the row's key, which is also its element's id
    def key_for(row)
      dom_id = @declaration.dom_id
      check_key(dom_id ? @component.instance_exec(row, &dom_id) : default_key(row))
    end

    # @return [String] a dom_id: declaration for messages
    def dom_id_example
      "`stream :#{name}, dom_id: ->(#{@declaration.row_name}) { … }`"
    end

    private

    def push(op)
      return if @collapsed

      # Only an unsubscribed or halted component queues across cycles; past
      # the bound a refill from the lambda replaces what it queued
      if @ops.size >= MAX_PENDING && (waiting = @component.stream_ops_waiting)
        LiveCable.warn_once(
          "[LiveCable] stream :#{name} of #{@component.live_id} queued #{MAX_PENDING} ops #{waiting}, so they " \
          'were dropped: it refills from its initial lambda when it renders'
        )
        @ops = []
        @reset = @collapsed = true
      else
        @ops << op
      end

      nil
    end

    def default_key(row)
      model = row.respond_to?(:to_model) ? row.to_model : row

      unless model.respond_to?(:to_key)
        raise LiveCable::Error, "stream :#{name}: the default dom id needs a model with to_key, and " \
                                "#{row_class(row)} has none. Declare #{dom_id_example}"
      end

      if model.to_key.nil?
        raise LiveCable::Error, "stream :#{name}: #{row_class(row)} has no id yet, so the default dom id would " \
                                "be the same for every unsaved row. Save it first, or declare #{dom_id_example}"
      end

      ActionView::RecordIdentifier.dom_id(row, name)
    end

    def row_class(row) = row.class.name || row.class.inspect

    def check_key(key)
      return key if key.is_a?(String) && key.match?(/\A\S+\z/)

      raise LiveCable::Error, "stream :#{name}: dom id #{key.inspect} is invalid: a row's dom id is its key and " \
                              "its element's id, so it must be a non-empty String with no whitespace"
    end
  end
end
