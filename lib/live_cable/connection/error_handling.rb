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
        return true if component.rescue_with_handler(error)

        handle_error(component, error)
        false
      end

      # Report an error and replace the component on the client with an
      # error box.
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
          Rails.error.report(error)

          html = error_html(component, error)

          # Destroy children first so their _status:destroy messages arrive before _error
          component&.owned_children&.each(&:destroy)

          # Broadcast the error - JS replaces the DOM and calls unsubscribe(),
          # which triggers LiveChannel#unsubscribed -> component.disconnect for server cleanup
          (channel || component)&.broadcast(_error: html)
        end
      end

      private

      def error_html(component, error)
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
