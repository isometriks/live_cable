# frozen_string_literal: true

module LiveCable
  module Delegation
    module Model
      extend Methods

      decorate_mutator :assign_attributes
      decorate_mutator :update

      # Setters, toggle!, reload and the like reach the record through here
      def method_missing(...) # rubocop:disable Style/MissingRespondToMissing -- SimpleDelegator defines it
        record = __getobj__
        writes = record.live_cable_writes

        begin
          super
        ensure
          notify_live_cable_observers unless record.live_cable_writes == writes
        end
      end
    end
  end
end
