# frozen_string_literal: true

module LiveCable
  class Component
    module Streaming
      extend ActiveSupport::Concern

      private

      def start_stream
        channel.stream_from(channel_name)
      end

      def stream_from(channel_name, callback = nil, coder: nil, &block)
        channel.stream_from(channel_name, coder:) do |payload|
          callback ||= block
          callback.call(payload)

          live_connection.broadcast_changeset
        end
      end
    end
  end
end
