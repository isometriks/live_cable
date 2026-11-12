# frozen_string_literal: true

module LiveCable
  class Component
    module Lifecycle
      extend ActiveSupport::Concern

      included do
        extend ActiveModel::Callbacks

        define_model_callbacks :connect, :disconnect, :render
      end

      def status
        subscribed? ? 'subscribed' : 'disconnected'
      end

      def subscribed?
        @subscribed
      end

      # @api private
      def connected?
        !channel.nil?
      end

      # @param channel [ActionCable::Channel::Base]
      def connect(channel)
        @channel = channel
        run_callbacks(:connect) { @subscribed = true }
        refuse! unless subscribed?
      ensure
        @channel = nil unless subscribed?
      end

      def disconnect
        run_callbacks :disconnect do
          stop_stream

          @channel = nil
          @previous_render_context&.clear
          @previous_render_context = nil
        end
      ensure
        live_connection&.remove_component(self)
        @live_connection = nil
      end

      def destroy
        broadcast_destroy

        # Destroy children as well
        owned_children.each(&:destroy)
      end

      # Stop the component because the person may no longer use it, from an
      # action, a callback, a stream callback or a render over the socket.
      # The client keeps its markup, marks it refused and dispatches
      # live:refused with the reason.
      #
      # @param reason [String, Symbol, nil]
      # @raise [LiveCable::Refused] always
      def refuse!(reason = nil)
        raise LiveCable::Refused, reason
      end

      # Allow the component to access the identified_by methods from the connection
      def respond_to_missing?(method_name, _include_private = false)
        return false unless channel

        channel.connection.identifiers.include?(method_name)
      end

      def method_missing(method_name, *, &)
        if channel.nil? || channel.connection.identifiers.exclude?(method_name)
          return super
        end

        channel.connection.public_send(method_name, *, &)
      end
    end
  end
end
