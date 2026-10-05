# frozen_string_literal: true

module LiveCable
  # Arel's in and not_in, which in_order_of also uses, only see an Array as a
  # list of values when it is Enumerable, and a reactive one isn't.
  module ArelPredications
    def in(other)
      super(Delegator.unwrap(other))
    end

    def not_in(other)
      super(Delegator.unwrap(other))
    end
  end
end
