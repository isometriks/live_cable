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

      extend_delegation_modules
    end

    # dup doesn't copy the singleton class, so the copy needs its modules again
    def initialize_dup(other)
      super

      extend_delegation_modules
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

    # Replaces every Delegator in value, value included, with the object it
    # wraps, copying an Array or Hash only when something inside it changes.
    #
    # @param value [Object]
    # @yieldparam delegator [Delegator] each Delegator it replaces
    # @return [Object]
    def self.unwrap(value, unwrapped = nil, &on_strip)
      while value.is_a?(Delegator)
        on_strip&.call(value)
        value = value.__getobj__
      end
      return value unless value.is_a?(::Array) || value.is_a?(::Hash)

      unwrapped ||= {}.compare_by_identity
      return unwrapped[value] if unwrapped.key?(value)

      unwrapped[value] = value
      copy = nil

      if value.is_a?(::Array)
        value.each_with_index do |child, index|
          plain = unwrap(child, unwrapped, &on_strip)
          (copy ||= value.dup)[index] = plain unless plain.equal?(child)
        end
      else
        value.each_pair do |key, child|
          plain = unwrap(child, unwrapped, &on_strip)
          (copy ||= value.dup)[key] = plain unless plain.equal?(child)
        end
      end

      unwrapped[value] = copy || value
    end

    # Check if a value's type can be wrapped in a Delegator.
    #
    # @param value [Object] The value to check
    # @return [Boolean] true if value can be delegated
    def self.supported?(value)
      Delegation::SUPPORTED.keys.any? { |c| value.is_a?(c) }
    end

    private

    # Extend with the appropriate delegation module based on the value's type
    def extend_delegation_modules
      Delegation::SUPPORTED.each do |klass, delegator|
        if __getobj__.is_a?(klass)
          extend delegator
        end
      end
    end

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
      # A Delegator stored inside raw data carries some other variable's observers
      value = value.__getobj__ while value.is_a?(Delegator)

      return value unless self.class.supported?(value)

      self.class.new(value).tap { |delegator| share_live_cable_observers_with(delegator) }
    end
  end
end
