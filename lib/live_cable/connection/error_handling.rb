# frozen_string_literal: true

module LiveCable
  class Connection
    module ErrorHandling
      extend ActiveSupport::Concern

      # Offer an error raised by the component's own code - an action, a
      # reactive write, a stream callback - to its rescue_from handlers, and
      # fall back to #handle_error when none matches.
      #
      # A handled error is a processed message, not a failed one: no _error
      # goes out, so the caller must still answer with a render or an _ack or
      # the client's loading state never clears.
      #
      # @param component [LiveCable::Component]
      # @param error [Exception]
      # @return [Boolean] true when a handler took the error
      def rescue_error(component, error)
        unless error.is_a?(LiveCable::Refused)
          begin
            return true if component.rescue_with_handler(error)
          rescue LiveCable::Refused => refusal
            error = refusal
          end
        end

        handle_error(component, error)
        false
      end

      # Report an error and replace the component on the client with an
      # error box. A refusal isn't reported, its _error is only for clients
      # older than 0.6, which don't know _refused, and it disconnects the
      # component at once rather than trusting the client to unsubscribe.
      #
      # @param component [LiveCable::Component, nil] nil when the failure
      #   happened before a component existed, such as a subscribe that could
      #   not build one
      # @param error [Exception]
      # @param channel [#broadcast, nil] the channel to deliver the _error
      #   through; needed when the component failed before it connected to
      #   one, or when there is no component at all
      def handle_error(component, error, channel: nil)
        synchronize do
          take_reply(component)
          containers[component.live_id].reset_changeset if component && containers.key?(component.live_id)
          component&.discard_stream_ops
          refusal = error.is_a?(LiveCable::Refused)
          Rails.error.report(error) unless refusal || error.is_a?(LiveCable::OutdatedClient)

          data = { _error: error_html(component, error) }
          data.merge!(_refused: true, _reason: error.reason) if refusal

          # Destroy children first so their _status:destroy messages arrive before _error
          component&.owned_children&.each(&:destroy)

          # Broadcast the error - JS replaces the DOM and calls unsubscribe(),
          # which triggers LiveChannel#unsubscribed -> component.disconnect for server cleanup
          (channel || component)&.broadcast(data)

          refuse_component(component) if refusal && component
        end
      end

      private

      def error_html(component, error)
        return "<p>#{ERB::Util.html_escape(error.message)}</p>" if error.is_a?(LiveCable::OutdatedClient)

        if LiveCable.configuration.verbose_errors
          name = component ? component.class.name : 'LiveCable'
          summary = "#{name} - #{error.class.name}: #{ERB::Util.html_escape(error.message)}"
          backtrace_html = <<~HTML
            <small>
              <ol>
                #{error.backtrace&.map { |line| "<li>#{ERB::Util.html_escape(line)}</li>" }&.join("\n")}
              </ol>
            </small>
          HTML
        else
          summary = 'An error occurred'
        end

        <<~HTML
          <details>
            <summary style="color: #f00; cursor: pointer">#{summary}</summary>
            #{backtrace_html}
          </details>
        HTML
      end
    end
  end
end
