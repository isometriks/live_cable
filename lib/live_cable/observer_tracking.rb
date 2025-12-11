# frozen_string_literal: true

module LiveCable
  # Mixin for objects that need to track and notify observers of changes.
  #
  # This module is included in both Delegator and ModelObserver to provide
  # a consistent interface for attaching observers and notifying them of changes.
  #
  # @example Usage in a Delegator
  #   class MyDelegator < SimpleDelegator
  #     include ObserverTracking
  #
  #     def mutate!
  #       # ... perform mutation ...
  #       notify_live_cable_observers  # Notify all observers
  #     end
  #   end
  #
  # Architecture:
  # - Objects can have multiple observers attached
  # - Each observer is associated with a specific variable name
  # - When the object changes, all observers are notified
  # - Observers then mark their variables as dirty in their containers
  module ObserverTracking
    # Attach an observer to track changes to a specific variable.
    # The same observer can be attached multiple times for different variables.
    #
    # @param observer [LiveCable::Observer] The observer to notify of changes
    # @param variable [Symbol] The reactive variable name this observer tracks
    # @return [void]
    #
    # @example
    #   observer = Observer.new(container)
    #   tags_array.add_live_cable_observer(observer, :tags)
    #   tags_array << 'ruby'  # Observer will be notified
    def add_live_cable_observer(observer, variable)
      observers = live_cable_observers_for(variable)

      unless observers.include?(observer)
        observers << observer
      end
    end

    private

    # Get the hash of all observers, keyed by variable name.
    #
    # @return [Hash<Symbol, Array<Observer>>] Variable name => observers
    def live_cable_observers
      @live_cable_observers ||= {}
    end

    # Get the list of observers for a specific variable.
    #
    # @param variable [Symbol] The variable name
    # @return [Array<Observer>] List of observers for this variable
    def live_cable_observers_for(variable)
      live_cable_observers[variable] ||= []
    end

    # Notify all attached observers that this object has changed.
    # Called automatically by mutative methods in delegation modules.
    #
    # @return [void]
    def notify_live_cable_observers
      live_cable_observers.each do |variable, observers|
        observers.each { |observer| observer.notify(variable) }
      end
    end
  end
end
