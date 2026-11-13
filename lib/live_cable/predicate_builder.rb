# frozen_string_literal: true

module LiveCable
  # Lets where(column: value) see the Array or Hash inside a reactive value
  # instead of treating the wrapper as a single scalar.
  module PredicateBuilder
    # An object rather than a lambda, so relations stay marshalable.
    class DelegatorHandler
      def initialize(predicate_builder)
        @predicate_builder = predicate_builder
      end

      def call(attribute, value)
        @predicate_builder.build(attribute, value.__getobj__)
      end
    end

    def initialize(...)
      super

      register_handler(Delegator, DelegatorHandler.new(self))
    end

    protected

    # A polymorphic association reads its _type from the record's class
    def expand_from_hash(attributes, &)
      super(Delegator.unwrap(attributes), &)
    end
  end
end
