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
            action = method(dispatch.name)
            action.arity.positive? ? action.call(dispatch.params) : action.call
          end
        end
      ensure
        @current_dispatch = nil
      end
    end
  end
end
