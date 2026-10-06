# frozen_string_literal: true

module LiveCable
  class Connection
    module Messaging
      extend ActiveSupport::Concern

      def receive(component, data)
        synchronize do
          reset_changeset

          return unless data['messages'].present?

          # An error broadcasts an _error, which is itself the batch's one
          # response - so a failed message must suppress the trailing _ack
          errored = false
          data['messages'].each do |message|
            errored = true unless action(component, message)
          end

          rendered = broadcast_changeset

          # Guarantee exactly one response per message batch so the client can
          # clear its loading state even when nothing changed
          component.broadcast_ack unless errored || rendered.include?(component)
        end
      end

      # @return [Boolean] true when the message was processed (including one a
      #   before_dispatch callback halted, or whose error the component's
      #   rescue_from took), false when an _error was broadcast in its place
      def action(component, data)
        return true unless data['_action']

        dispatch = Dispatch.from_message(data)
        ensure_exposed(component, dispatch)
        component.perform_dispatch(dispatch)

        true
      rescue LiveCable::Forbidden => e
        handle_error(component, e)
        false
      rescue StandardError => e
        rescue_error(component, e)
      end

      private

      def ensure_exposed(component, dispatch)
        if dispatch.reactive?
          return if component.class.writable_reactive_variables.include?(dispatch.name)

          raise LiveCable::Forbidden, "Non-writable reactive variable: #{dispatch.name}"
        end

        return if component.class.allowed_actions.include?(dispatch.name)

        raise LiveCable::Forbidden, "Unauthorized action: #{dispatch.name}"
      end
    end
  end
end
