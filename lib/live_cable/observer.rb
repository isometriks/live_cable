# frozen_string_literal: true

module LiveCable
  # Observer pattern implementation for tracking changes to reactive variables.
  #
  # The Observer is attached to delegated values (Arrays, Hashes, ActiveRecord models)
  # and notifies the container when changes occur. This enables automatic re-rendering
  # of components when their data changes.
  #
  # @example Basic usage
  #   container = Container.new
  #   observer = Observer.new(container)
  #   observer.notify(:username)  # Marks :username as dirty in the container
  #
  # Architecture:
  # - Each Container has one Observer instance
  # - Delegators (Array/Hash wrappers) hold references to observers
  # - When a mutative method is called on a delegator, it notifies all its observers
  # - The observer marks the variable as dirty in the container's changeset
  # - After processing a message, the connection broadcasts changes to all dirty components
  class Observer
    # @param container [LiveCable::Container] The container to notify of changes
    def initialize(container)
      @container = container
    end

    # Notify the container that a variable has changed.
    # This marks the variable as "dirty" so the component will be re-rendered.
    #
    # @param variable [Symbol] The name of the reactive variable that changed
    # @return [void]
    #
    # @example
    #   observer.notify(:tags)  # Component will re-render because :tags changed
    def notify(variable)
      container.mark_dirty(variable)
    end

    private

    # @return [LiveCable::Container]
    attr_reader :container
  end
end
