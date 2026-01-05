# frozen_string_literal: true

module LiveCable
  class Component
    module Lifecycle
      extend ActiveSupport::Concern

      included do
        attr_reader :rendered, :defaults
      end

      def status
        subscribed? ? 'subscribed' : 'disconnected'
      end

      def subscribed?
        @subscribed
      end

      # @param channel [ActionCable::Channel::Base]
      def connect(channel)
        @channel = channel

        start_stream
        connected
        broadcast_subscribe
      end

      def disconnect
        live_connection&.remove_component(self)
        stop_stream

        @channel = nil
        @previous_render_context&.clear
        @previous_render_context = nil
        @live_connection = nil

        disconnected
      end

      def destroy
        broadcast_destroy
      end

      # Lifecycle hooks - override in subclasses to add custom behavior
      def connected
        # Called when the component is first subscribed to the channel
      end

      def disconnected
        # Called when the component is unsubscribed from the channel
      end

      def before_render
        # Called before each render/broadcast
      end

      def after_render
        # Called after each render/broadcast
      end

      # Allow the component to access the identified_by methods from the connection
      def respond_to_missing?(method_name, _include_private = false)
        return false unless channel

        channel.connection.identifiers.include?(method_name)
      end

      def method_missing(method_name, *, &)
        channel.connection.public_send(method_name, *, &)
      end
    end
  end
end
