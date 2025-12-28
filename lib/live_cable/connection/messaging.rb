# frozen_string_literal: true

module LiveCable
  class Connection
    module Messaging
      extend ActiveSupport::Concern

      def receive(component, data)
        check_csrf_token(data)
        reset_changeset

        return unless data['messages'].present?

        data['messages'].each do |message|
          action(component, message)
        end

        broadcast_changeset
      end

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
      rescue StandardError => e
        handle_error(component, e)
      end

      def reactive(component, data)
        unless component.all_reactive_variables.include?(data['name'].to_sym)
          raise Error, "Invalid reactive variable: #{data['name']}"
        end

        component.public_send("#{data['name']}=", data['value'])
      rescue StandardError => e
        handle_error(component, e)
      end

      private

      def check_csrf_token(data)
        session = request.session
        return unless session[:_csrf_token]

        token = data['_csrf_token']
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
