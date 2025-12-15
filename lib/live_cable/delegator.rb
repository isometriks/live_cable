# frozen_string_literal: true

module LiveCable
  module Delegation
    extend ActiveSupport::Autoload

    autoload :Array
    autoload :Hash
    autoload :Methods
    autoload :Model

    SUPPORTED = {
      ::ActiveRecord::Base => Delegation::Model,
      ::Array => Delegation::Array,
      ::Hash => Delegation::Hash,
    }.freeze
  end

  class Delegator < SimpleDelegator
    include ObserverTracking

    def initialize(value, variable, observer = nil)
      super(value)

      if observer
        add_live_cable_observer(observer, variable)
      end

      Delegation::SUPPORTED.each do |klass, delegator|
        if value.is_a?(klass)
          extend delegator
        end
      end
    end

    def self.create_if_supported(value, variable, observer)
      if Delegation::SUPPORTED.keys.any? { |c| value.is_a?(c) }
        return new(value, variable, observer)
      end

      value
    end

    private

    def create_delegator(value)
      # Create a delegator without an observer, as it will inherit from parent
      self.class.new(value, variable, observer)
    end
  end
end
