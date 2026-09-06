# frozen_string_literal: true

module LiveCable
  class Connection
    module Messaging
      extend ActiveSupport::Concern

      def receive(component, data)
        check_csrf_token(data)
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

      # A token the page can send once this socket is fresh, minted from the
      # session captured at the handshake. It is issued only when the handshake
      # came from the application's own origin or one ActionCable is configured
      # to allow: browsers put the opening page's origin on every WebSocket
      # handshake and a cross-site page cannot forge it, so the token is exactly
      # as hard to obtain as the page's own <meta name="csrf-token"> - whatever
      # the application has done to ActionCable's own origin check.
      #
      # @return [String, nil]
      def csrf_token
        return unless request.session[:_csrf_token]
        return unless trusted_origin?

        csrf_checker.token
      end

      private

      # Mirrors ActionCable's allow_request_origin? without its
      # disable_request_forgery_protection escape hatch
      def trusted_origin?
        origin = request.get_header('HTTP_ORIGIN')
        return false if origin.blank?

        scheme = request.ssl? ? 'https' : 'http'
        return true if origin == "#{scheme}://#{request.get_header('HTTP_HOST')}"

        Array(ActionCable.server.config.allowed_request_origins).any? do |allowed|
          allowed.is_a?(Regexp) ? allowed.match?(origin) : allowed == origin
        end
      end

      # Tokens are verified against the session captured at the WebSocket
      # handshake - a socket never sees cookies set after it opened. When the
      # session's token rotates behind an open socket (Devise does this on
      # every sign-in), pages rendered from then on carry a token this
      # connection cannot verify, so the channel answers InvalidCsrfToken by
      # asking the client to reconnect rather than failing the message. The
      # fresh socket then hands the page a token it can verify (#csrf_token).
      def check_csrf_token(data)
        session = request.session
        return unless session[:_csrf_token]

        token = data['_csrf_token']
        unless csrf_checker.valid?(session, token)
          raise LiveCable::InvalidCsrfToken, 'Invalid CSRF token'
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
