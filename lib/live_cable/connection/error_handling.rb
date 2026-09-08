# frozen_string_literal: true

module LiveCable
  class Connection
    module ErrorHandling
      extend ActiveSupport::Concern

      # Report an error and replace the component on the client with an
      # error box.
      #
      # @param component [LiveCable::Component, nil] nil when the failure
      #   happened before a component existed, such as a subscribe that could
      #   not build one
      # @param error [Exception]
      # @param channel [#broadcast, nil] where to deliver the _error when there
      #   is no component to deliver it through
      def handle_error(component, error, channel: nil)
        Rails.error.report(error)

        html = error_html(component, error)

        # Broadcast the error - JS replaces the DOM and calls unsubscribe(),
        # which triggers LiveChannel#unsubscribed -> component.disconnect for server cleanup
        if component
          # Destroy children first so their _status:destroy messages arrive before _error
          component.rendered_children.each(&:destroy)
          component.broadcast(_error: html)
        else
          channel&.broadcast(_error: html)
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
