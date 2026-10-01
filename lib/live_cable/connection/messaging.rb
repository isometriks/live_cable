# frozen_string_literal: true

module LiveCable
  class Connection
    module Messaging
      extend ActiveSupport::Concern

      def receive(component, data)
        synchronize do
          reset_changeset

          return unless data['messages'].present?

          @reply_to = component
          @carried = Set.new

          data['messages'].each do |message|
            action(component, message)
          end

          broadcast_changeset

          # Guarantee exactly one reply per message batch so the client can
          # clear its loading state: the component's own render, an _error,
          # or this
          component.broadcast_ack(rendered: @carried.include?(component.live_id)) if take_reply(component)
        ensure
          @reply_to = nil
          @carried = nil
        end
      end

      # Notes the children a frame sent during a message batch rendered inline
      #
      # @param children [Hash{String => Hash}, nil] the frame's c
      def carried(children)
        @carried&.merge(children.keys) if children
      end

      # @return [Boolean] true, once, for the frame that answers the message
      #   batch the component sent; never while one of its messages still runs
      def take_reply(component)
        return false unless component && @reply_to.equal?(component) && !component.current_dispatch

        @reply_to = nil
        true
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
          return if component.class.client_writable?(dispatch.name)

          raise LiveCable::Forbidden, "Non-writable reactive variable: #{dispatch.name}"
        end

        return if component.class.allowed_actions.include?(dispatch.name)

        raise LiveCable::Forbidden, "Unauthorized action: #{dispatch.name}"
      end
    end
  end
end
