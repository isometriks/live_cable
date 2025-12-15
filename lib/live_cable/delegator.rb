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

    def initialize(value)
      super

      Delegation::SUPPORTED.each do |klass, delegator|
        if value.is_a?(klass)
          extend delegator
        end
      end
    end

    def self.create_if_supported(value, variable, observer)
      if Delegation::SUPPORTED.keys.any? { |c| value.is_a?(c) }
        return new(value).tap do |delegator|
          delegator.add_live_cable_observer(observer, variable)
        end
      end

      value
    end

    private

    def create_delegator(value)
      # Create a delegator that also takes observers from parent
      self.class.new(value).tap do |delegator|
        live_cable_observers.each do |variable, observers|
          observers.each { |observer| delegator.add_live_cable_observer(observer, variable) }
        end
      end
    end
  end
end
