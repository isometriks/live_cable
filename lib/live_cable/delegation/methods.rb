# frozen_string_literal: true

module LiveCable
  module Delegation
    module Methods
      private

      def decorate_getters(methods)
        methods.each do |method|
          decorate_getter(method)
        end
      end

      def decorate_getter(method)
        define_method(method) do |*pos, **kwargs, &block|
          create_delegator(
            __getobj__.method(method).call(*pos, **kwargs, &block)
          )
        end
      end

      # A new collection is only wrapped when it holds something trackable, so
      # a plain list of scalars stays a real Array.
      def decorate_collection_getters(methods)
        methods.each do |method|
          define_method(method) do |*pos, **kwargs, &block|
            result = __getobj__.method(method).call(*pos, **kwargs, &block)

            result.any? { |value| Delegator.supported?(value) } ? create_delegator(result) : result
          end
        end
      end

      # Runs Enumerable's implementation against the delegator, so elements
      # arrive through its wrapping #each.
      def decorate_iterators(methods)
        methods.each do |method|
          iterator = ::Enumerable.instance_method(method)

          define_method(method) do |*args, &block|
            iterator.bind_call(self, *args, &block)
          end
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
