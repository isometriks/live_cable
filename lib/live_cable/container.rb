# frozen_string_literal: true

module LiveCable
  # Storage for reactive variable values with automatic change tracking.
  #
  # A Container is a Hash subclass that stores the values of reactive variables
  # for a single component instance. It automatically wraps supported types
  # (Arrays, Hashes, ActiveRecord models) in Delegators that track mutations.
  #
  # @example Basic usage
  #   container = Container.new
  #   container[:username] = "john"           # Stored as-is
  #   container[:tags] = ['ruby', 'rails']    # Wrapped in Delegator
  #   container[:tags] << 'rspec'             # Automatically marks :tags as dirty
  #
  # Architecture:
  # - Each component instance has its own Container (identified by live_id)
  # - Shared reactive variables use a special SHARED_CONTAINER
  # - During message processing, mutations are tracked in a changeset
  # - After message processing, components with dirty changesets are re-rendered
  # - Changesets are reset after broadcasting updates
  #
  # Change Tracking:
  # 1. Value is stored via []=
  # 2. If value is an Array/Hash/Model, it's wrapped in a Delegator
  # 3. Delegator attaches observers to the value
  # 4. When value is mutated, observers mark the variable as dirty
  # 5. Component re-renders if changeset contains the variable
  class Container < Hash
    # @param args [Array] Arguments passed to Hash.new
    def initialize(...)
      super
      @changeset = []
    end

    # Store a value in the container, automatically wrapping supported types
    # in Delegators for change tracking.
    #
    # @param key [Symbol] The reactive variable name
    # @param value [Object] The value to store
    # @return [Object] The stored value (possibly wrapped in a Delegator)
    #
    # @example Storing different types
    #   container[:count] = 0                    # Number - stored as-is
    #   container[:tags] = ['ruby']              # Array - wrapped in Delegator
    #   container[:user] = User.new              # ActiveRecord - wrapped in Delegator
    def []=(key, value)
      # ActiveRecord models get observers attached directly
      if value.class < ModelObserver
        value.add_live_cable_observer(observer, key)
      end

      # If value is already a Delegator, add observer and store as-is
      if value.is_a?(Delegator)
        value.add_live_cable_observer(observer, key)
        super
      else
        # Wrap supported types in Delegators for change tracking
        super(key, Delegator.create_if_supported(value, key, observer))
      end
    end

    # Mark one or more variables as dirty (changed).
    # Dirty variables will trigger a re-render of their component.
    #
    # @param variables [Array<Symbol>] Variable names to mark as dirty
    # @return [void]
    #
    # @example
    #   container.mark_dirty(:username, :email)
    def mark_dirty(*variables)
      @changeset |= variables # Union operator keeps values unique
    end

    # Returns the list of variables that have changed during this message cycle.
    #
    # @return [Array<Symbol>] List of dirty variable names
    attr_reader :changeset

    # Check if any variables have changed.
    #
    # @return [Boolean] true if changeset is not empty
    def changed?
      !@changeset.empty?
    end

    # Clear the changeset after broadcasting updates.
    # Called by Connection after all components have been re-rendered.
    #
    # @return [void]
    def reset_changeset
      @changeset = []
    end

    # Get or create the observer for this container.
    # Each container has exactly one observer instance.
    #
    # @return [LiveCable::Observer] The observer instance
    def observer
      @observer ||= Observer.new(self)
    end
  end
end
