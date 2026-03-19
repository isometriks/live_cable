# frozen_string_literal: true

module Live
  class ErrorTest < LiveCable::Component
    STREAM_NAME = 'live_cable_error_stream_test'

    reactive :raise_on_render, -> { false }

    actions :trigger_error, :trigger_render_error, :subscribe_to_error_stream, :broadcast_to_error_stream

    def trigger_error
      raise 'Something went wrong'
    end

    def trigger_render_error
      self.raise_on_render = true
    end

    def subscribe_to_error_stream
      stream_from(STREAM_NAME) { raise 'Stream callback error' }
    end

    def broadcast_to_error_stream
      ActionCable.server.broadcast(STREAM_NAME, {})
    end
  end
end
