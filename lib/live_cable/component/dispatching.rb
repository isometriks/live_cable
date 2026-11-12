# frozen_string_literal: true

module LiveCable
  class Component
    module Dispatching
      extend ActiveSupport::Concern

      included do
        define_model_callbacks :dispatch, only: :before
      end

      # @return [LiveCable::Dispatch, nil] The client message being dispatched
      attr_reader :current_dispatch

      # Run the before_dispatch callbacks, then the action or reactive write
      # the message asks for, unless a callback threw :abort.
      #
      # @param dispatch [LiveCable::Dispatch] Already checked against the
      #   component's actions and writable variables
      def perform_dispatch(dispatch)
        @current_dispatch = dispatch

        run_callbacks :dispatch do
          if dispatch.reactive?
            public_send("#{dispatch.name}=", dispatch.value)
          else
            # A reactive variable named method replaces Kernel#method
            action = Kernel.instance_method(:method).bind_call(self, dispatch.name)
            takes_params?(action) ? action.call(dispatch.params) : action.call
          end
        end
      ensure
        @current_dispatch = nil
      end

      private

      # A splat over another method is a forwarder (a (*) wrapper, an RSpec
      # stub), and so is an anonymous one (delegate, method_missing): it takes
      # what the method it wraps takes, if any.
      def takes_params?(action)
        action.parameters.any? do |type, name|
          case [type, name]
          in [:rest, _] if action.super_method then takes_params?(action.super_method)
          in [:req | :opt, _] then true
          in [:rest, _] then !name.nil? && name != :*
          else false
          end
        end
      end
    end
  end
end
