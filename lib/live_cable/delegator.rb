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
    def initialize(value, variable, container)
      super(value)

      @variable = variable
      @container = container

      Delegation::SUPPORTED.each do |klass, delegator|
        if value.is_a?(klass)
          extend delegator
        end
      end
    end

    def self.create_if_supported(value, variable, container)
      if Delegation::SUPPORTED.keys.any? { |c| value.is_a?(c) }
        return new(value, variable, container)
      end

      value
    end

    private

    # @return [Symbol]
    attr_reader :variable

    # @return [Container]
    attr_reader :container

    def create_delegator(value)
      self.class.create_if_supported(value, variable, container)
    end

    def mark_dirty
      container.mark_dirty(variable)
    end
  end
end
