# frozen_string_literal: true

module LiveCable
  class Connection
    module ErrorHandling
      extend ActiveSupport::Concern

      def handle_error(component, error)
        # Give the component a chance to handle the error itself via a
        # `rescue_from` handler. When one matches, rescue_with_handler returns
        # the exception (truthy) and we skip the default error broadcast - any
        # reactive state the handler changed is picked up by the surrounding
        # broadcast_changeset cycle and re-rendered normally.
        return if component && component.rescue_with_handler(error)

        Rails.error.report(error)

        if LiveCable.configuration.verbose_errors
          summary = "#{component.class.name} - #{error.class.name}: #{ERB::Util.html_escape(error.message)}"
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

        html = <<~HTML
          <details>
            <summary style="color: #f00; cursor: pointer">#{summary}</summary>
            #{backtrace_html}
          </details>
        HTML

        # Destroy children first so their _status:destroy messages arrive before _error
        component.rendered_children.each(&:destroy)

        # Broadcast the error - JS replaces the DOM and calls unsubscribe(),
        # which triggers LiveChannel#unsubscribed -> component.disconnect for server cleanup
        component.broadcast(_error: html)
      end
    end
  end
end
