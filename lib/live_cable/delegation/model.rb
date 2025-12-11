# frozen_string_literal: true

module LiveCable
  module Delegation
    module Model
      extend Methods

      decorate_mutator :assign_attributes
      decorate_mutator :update
    end
  end
end
