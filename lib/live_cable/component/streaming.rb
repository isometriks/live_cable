# frozen_string_literal: true

module LiveCable
  class Component
    module Streaming
      extend ActiveSupport::Concern

      private

      def start_stream
        channel.stream_from(channel_name)
      end

      def stop_stream
        channel.stop_stream_from(channel_name)

        # Stop all additional streams started via stream_from
        additional_streams.each do |stream_name|
          channel.stop_stream_from(stream_name)
        end
      end

      def stream_from(channel_name, callback = nil, coder: nil, &block)
        additional_streams << channel_name

        channel.stream_from(channel_name, coder:) do |payload|
          callback ||= block
          callback.call(payload)

          live_connection.broadcast_changeset
        end
      end

      def additional_streams
        @additional_streams ||= []
      end
    end
  end
end
