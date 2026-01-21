# frozen_string_literal: true

module LiveCable
  class Component
    module Lifecycle
      extend ActiveSupport::Concern

      included do
        extend ActiveModel::Callbacks

        define_model_callbacks :connect, :disconnect, :render

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
        run_callbacks :connect do
          @channel = channel
          start_stream
          broadcast_subscribe
        end
      end

      def disconnect
        run_callbacks :disconnect do
          live_connection&.remove_component(self)
          stop_stream

          @channel = nil
          @previous_render_context&.clear
          @previous_render_context = nil
          @live_connection = nil
        end
      end

      def destroy
        broadcast_destroy
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
