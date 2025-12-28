# frozen_string_literal: true

module LiveCable
  class Connection
    module ChannelManagement
      extend ActiveSupport::Concern

      def set_channel(component, channel)
        channels[component] = channel
      end

      def get_channel(component)
        channels[component]
      end

      def remove_channel(component)
        channels.delete(component)
      end

      def channel_name
        "live_#{session_id}"
      end

      private

      # @return [Hash<LiveCable::Component, ActionCable::Channel::Base>]
      attr_reader :channels
    end
  end
end
