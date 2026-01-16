# frozen_string_literal: true

module LiveCable
  # Delegation modules for different data types.
  # Each module defines which methods should trigger change notifications.
  module Delegation
    # Maps Ruby classes to their delegation modules.
    # When a value of one of these types is stored in a container,
    # it will be wrapped in a Delegator and extended with the appropriate module.
    SUPPORTED = {
      ::ActiveRecord::Base => Delegation::Model,
      ::Array => Delegation::Array,
      ::Hash => Delegation::Hash,
    }.freeze
  end

  # Wraps mutable objects (Arrays, Hashes, Models) to track changes.
  #
  # The Delegator uses Ruby's SimpleDelegator to transparently wrap objects
  # and intercept method calls. When mutative methods are called, observers
  # are notified so the component can be re-rendered.
  #
  # @example Automatic wrapping
  #   container[:tags] = ['ruby', 'rails']
  #   # Container automatically wraps the array in a Delegator
  #   container[:tags] << 'rspec'  # Triggers observer notification
  #
  # @example Manual creation
  #   delegator = Delegator.new(['ruby', 'rails'])
  #   delegator.add_live_cable_observer(observer, :tags)
  #   delegator << 'rspec'  # Notifies observer
  #
  # Architecture:
  # - Delegator extends SimpleDelegator to wrap the target object
  # - Dynamically extends with type-specific delegation modules (Array/Hash/Model)
  # - Each delegation module decorates mutative methods to notify observers
  # - Getter methods are not decorated (no notification on read)
  # - Nested structures automatically get wrapped in new Delegators with the same observers
  #
  # Supported Types:
  # - Array: Tracks push, <<, delete, etc.
  # - Hash: Tracks []=, delete, merge!, etc.
  # - ActiveRecord::Base: Tracks assign_attributes, update, etc.
  class Delegator < SimpleDelegator
    include ObserverTracking

    # @param value [Object] The object to wrap and track
    def initialize(value)
      super

      # Extend with the appropriate delegation module based on value's type
      Delegation::SUPPORTED.each do |klass, delegator|
        if value.is_a?(klass)
          extend delegator
        end
      end
    end

    # Factory method to create a Delegator only if the value's type is supported.
    # Returns the original value unchanged if not supported.
    #
    # @param value [Object] The value to potentially wrap
    # @param variable [Symbol] The reactive variable name
    # @param observer [Observer] The observer to attach
    # @return [Delegator, Object] Wrapped value or original value
    def self.create_if_supported(value, variable, observer)
      if supported?(value)
        return new(value).tap do |delegator|
          delegator.add_live_cable_observer(observer, variable)
        end
      end

      value
    end

    # Check if a value's type can be wrapped in a Delegator.
    #
    # @param value [Object] The value to check
    # @return [Boolean] true if value can be delegated
    def self.supported?(value)
      Delegation::SUPPORTED.keys.any? { |c| value.is_a?(c) }
    end

    private

    # Create a new Delegator for nested values (e.g., nested arrays/hashes).
    # Propagates all observers from the parent delegator to the child.
    #
    # @param value [Object] The nested value to wrap
    # @return [Delegator, Object] Wrapped value or original if not supported
    #
    # @example Nested arrays
    #   outer = Delegator.new([['inner']])
    #   inner = outer[0]  # Returns a Delegator wrapping ['inner']
    #   inner << 'new'    # Notifies same observers as outer
    def create_delegator(value)
      return value unless self.class.supported?(value)

      # Create new delegator and propagate all observers from parent
      self.class.new(value).tap do |delegator|
        live_cable_observers.each do |variable, observers|
          observers.each { |observer| delegator.add_live_cable_observer(observer, variable) }
        end
      end
    end
  end
end
