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

          # Held across the callback and the render together: the callback's
          # writes are what race an action on another worker, so locking only
          # the broadcast would leave the race in place.
          live_connection.synchronize do
            live_connection.reset_changeset

            # A rescue_from handler that takes the error may have changed state
            # to show it, so render in that case too; after an _error there is
            # nothing left to render into.
            handled = begin
              callback.call(payload)
              true
            rescue StandardError => error
              live_connection.rescue_error(self, error)
            end

            live_connection.broadcast_changeset if handled
          # Nothing above this rescues a stream callback, so a raising
          # rescue_from handler or render must not escape to ActionCable
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
