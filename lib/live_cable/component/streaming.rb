# frozen_string_literal: true

module LiveCable
  class Component
    module Streaming
      extend ActiveSupport::Concern

      private

      def stop_stream
        additional_streams.each do |stream_name|
          channel.stop_stream_from(stream_name)
        end
      end

      def stream_from(channel_name, callback = nil, coder: nil, &block)
        additional_streams << channel_name

        channel.stream_from(channel_name, coder:) do |payload|
          callback ||= block

          # A stream broadcast can arrive on a worker thread while another
          # message for this connection is being processed; serialize the
          # callback + re-render with everything else that touches the
          # connection's shared state.
          live_connection.synchronize do
            callback.call(payload)
            live_connection.broadcast_changeset
          rescue StandardError => error
            live_connection.handle_error(self, error)
          end
        end
      end

      def additional_streams
        @additional_streams ||= []
      end
    end
  end
end
