# frozen_string_literal: true

module LiveCable
  module Testing
    # Stand-in for an ActionCable channel. Records streams started via
    # stream_from so tests can trigger their callbacks with receive_stream,
    # and payloads sent by components.
    class TestChannel
      # @return [Hash<String, Hash>] Stream name => { coder:, callback: }
      attr_reader :streams

      # @return [Array<Hash>] Payloads sent by components through this channel
      attr_reader :transmissions

      # @return [LiveCable::Testing::TestCableConnection]
      attr_reader :connection

      def initialize(identifiers = {})
        @streams = {}
        @transmissions = []
        @connection = TestCableConnection.new(identifiers)
      end

      def broadcast(data)
        @transmissions << data
      end

      def stream_from(name, coder: nil, &block)
        @streams[name] = { coder:, callback: block }
      end

      def stop_stream_from(name)
        @streams.delete(name)
      end

      # Simulate an external broadcast arriving on a stream.
      # The payload goes through the stream's coder round trip, so a Hash
      # payload arrives with string keys just like a production broadcast.
      #
      # @param name [String] The stream name passed to stream_from
      # @param payload [Object] The broadcast payload
      def broadcast_to(name, payload)
        stream = @streams.fetch(name) do
          raise LiveCable::Error, "Component is not streaming from #{name.inspect} " \
                                  "(active streams: #{@streams.keys.inspect})"
        end

        callback = stream[:callback]
        raise LiveCable::Error, "Stream #{name.inspect} has no callback" unless callback

        coder = stream[:coder]
        payload = coder.decode(coder.encode(payload)) if coder

        callback.call(payload)
      end
    end
  end
end
