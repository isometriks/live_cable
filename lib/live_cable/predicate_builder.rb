# frozen_string_literal: true

module LiveCable
  # Lets where(column: value) see the Array or Hash inside a reactive value
  # instead of treating the wrapper as a single scalar.
  module PredicateBuilder
    def initialize(...)
      super

      register_handler(Delegator, ->(attribute, value) { build(attribute, value.__getobj__) })
    end
  end
end
