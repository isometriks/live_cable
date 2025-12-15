# frozen_string_literal: true

module LiveCable
  module Delegation
    module Methods
      private

      def decorate_getter(method)
        define_method(method) do |*pos, **kwargs, &block|
          create_delegator(
            __getobj__.method(method).call(*pos, **kwargs, &block)
          )
        end
      end

      def decorate_mutators(methods)
        methods.each do |method|
          decorate_mutator(method)
        end
      end

      def decorate_mutator(method)
        define_method(method) do |*pos, **kwargs, &block|
          notify_live_cable_observers

          __getobj__.method(method).call(*pos, **kwargs, &block)
        end
      end
    end
  end
end
