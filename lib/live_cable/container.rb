# frozen_string_literal: true

module LiveCable
  class Container < Hash
    def initialize(...)
      super
      @changeset = []
    end

    def []=(key, value)
      if value.class < ModelObserver
        value.add_live_cable_observer(observer, key)
      end

      super(key, Delegator.create_if_supported(value, key, self))
    end

    # Track which keys in this container have changed during a message cycle
    # @param variables [Array<Symbol>]
    def mark_dirty(*variables)
      @changeset |= variables # keep unique
    end

    # @return [Array<Symbol>]
    attr_reader :changeset

    # @return [Boolean]
    def changed?
      !@changeset.empty?
    end

    def reset_changeset
      @changeset = []
    end

    def observer
      @observer ||= Observer.new(self)
    end
  end
end
