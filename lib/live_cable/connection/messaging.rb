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

          data['messages'].each do |message|
            action(component, message)
          end

          broadcast_changeset

          # Guarantee exactly one reply per message batch so the client can
          # clear its loading state: the component's own render, an _error,
          # or this
          component.broadcast_ack if take_reply(component)
        ensure
          @reply_to = nil
        end
      end

      # @return [Boolean] true, once, for the frame that answers the message
      #   batch the component sent
      def take_reply(component)
        return false unless component && @reply_to.equal?(component)

        @reply_to = nil
        true
      end

      # @return [Boolean] true when the message was processed (including an
      #   error the component's rescue_from took), false when an _error was
      #   broadcast in its place
      def action(component, data)
        params = parse_params(data)

        if data['_action']
          action = data['_action'].to_s.to_sym

          if action == :_reactive
            return reactive(component, data)
          end

          unless component.class.allowed_actions.include?(action)
            raise LiveCable::Forbidden, "Unauthorized action: #{action}"
          end

          method = component.method(action)

          if method.arity.positive?
            method.call(params)
          else
            method.call
          end
        end

        true
      rescue LiveCable::Forbidden => e
        handle_error(component, e)
        false
      rescue StandardError => e
        rescue_error(component, e)
      end

      # @return [Boolean] true when applied or rescued by the component, false
      #   when an _error was broadcast in its place
      def reactive(component, data)
        unless component.class.writable_reactive_variables.include?(data['name'].to_s.to_sym)
          raise LiveCable::Forbidden, "Non-writable reactive variable: #{data['name']}"
        end

        component.public_send("#{data['name']}=", data['value'])

        true
      rescue LiveCable::Forbidden => e
        handle_error(component, e)
        false
      rescue StandardError => e
        rescue_error(component, e)
      end

      private

      def parse_params(data)
        params = data['params'] || ''

        ActionController::Parameters.new(
          ActionDispatch::ParamBuilder.from_pairs(
            ActionDispatch::QueryParser.each_pair(params)
          )
        )
      end
    end
  end
end
