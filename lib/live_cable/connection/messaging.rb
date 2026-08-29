# frozen_string_literal: true

module LiveCable
  class Connection
    module Messaging
      extend ActiveSupport::Concern

      def receive(component, data)
        check_csrf_token(data)

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

      # @return [Boolean] true when the message was processed, false when an
      #   error was handled (and an _error broadcast in its place)
      def action(component, data)
        params = parse_params(data)

        if data['_action']
          action = data['_action']&.to_sym

          if action == :_reactive
            return reactive(component, data)
          end

          unless component.class.allowed_actions.include?(action)
            raise LiveCable::Error, "Unauthorized action: #{action}"
          end

          method = component.method(action)

          if method.arity.positive?
            method.call(params)
          else
            method.call
          end
        end

        true
      rescue StandardError => e
        handle_error(component, e)
        false
      end

      # @return [Boolean] true when applied, false when an error was handled
      def reactive(component, data)
        unless component.class.writable_reactive_variables.include?(data['name'].to_sym)
          raise LiveCable::Error, "Non-writable reactive variable: #{data['name']}"
        end

        component.public_send("#{data['name']}=", data['value'])

        true
      rescue StandardError => e
        handle_error(component, e)
        false
      end

      private

      def check_csrf_token(data)
        session = request.session
        token = data['_csrf_token']

        unless session[:_csrf_token]
          # No token to check against. Reject only when the app has opted into
          # requiring one; otherwise skip (e.g. session-less/token auth).
          return unless LiveCable.configuration.require_csrf_token

          raise LiveCable::Error, 'CSRF token required but the session has none'
        end

        unless csrf_checker.valid?(session, token)
          raise LiveCable::Error, 'Invalid CSRF token'
        end
      end

      def csrf_checker
        @csrf_checker ||= LiveCable::CsrfChecker.new(request)
      end

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
