# frozen_string_literal: true

module LiveCable
  class Connection
    module ErrorHandling
      extend ActiveSupport::Concern

      def handle_error(component, error)
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
