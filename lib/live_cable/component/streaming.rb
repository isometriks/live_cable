# frozen_string_literal: true

module LiveCable
  class Component
    module Streaming
      extend ActiveSupport::Concern

      Stream = Struct.new(:callback, :coder, :replaced)
      private_constant :Stream

      private

      def stop_stream
        additional_streams.each_key do |stream_name|
          channel.stop_stream_from(stream_name)
        end

        additional_streams.clear
      end

      def stop_stream_from(channel_name)
        channel.stop_stream_from(channel_name)
        additional_streams.delete(channel_name)
      end

      def stream_from(channel_name, callback = nil, coder: nil, &block)
        stream = additional_streams[channel_name]
        return stream.callback = callback || block if stream && stream.coder == coder

        if stream
          stop_stream_from(channel_name)
          # ActionCable subscribes late, so a handler started in this job outlives the stop
          stream.replaced = true
        end
        stream = additional_streams[channel_name] = Stream.new(callback || block, coder)

        channel.stream_from(channel_name, coder:) do |payload|
          # Stopping a stream, as disconnect does, can't take back a broadcast
          # already queued, which may run after it or wait on the lock below
          connection = live_connection
          next unless connection

          # Held across the callback and the render together: the callback's
          # writes are what race an action on another worker, so locking only
          # the broadcast would leave the race in place.
          connection.synchronize do
            next unless live_connection == connection
            next if stream.replaced || !additional_streams.key?(channel_name)

            begin
              stream.callback.call(payload)
            rescue StandardError, ScriptError => error
              connection.rescue_error(self, error)
            end

            # Even after an _error, as for an action: the callback may have
            # changed other components, such as through a shared variable
            connection.broadcast_changeset
          # Nothing above this rescues a stream callback, so a raising
          # rescue_from handler or render must not escape to ActionCable
          rescue StandardError, ScriptError => error
            connection.handle_error(self, error)
          end
        end
      end

      def additional_streams
        @additional_streams ||= {}
      end
    end
  end
end
