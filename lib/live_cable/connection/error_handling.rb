# frozen_string_literal: true

module LiveCable
  class Connection
    module ErrorHandling
      extend ActiveSupport::Concern

      private

      def handle_error(component, error)
        html = <<~HTML
          <details>
            <summary style="color: #f00; cursor: pointer">
              <strong>#{component.class.name}</strong> - #{error.class.name}: #{error.message}
            </summary>
            <small>
              <ol>
                #{error.backtrace&.map { "<li>#{it}</li>" }&.join("\n")}
              </ol>
            </small>
          </details>
        HTML

        component.broadcast(_refresh: html)
      ensure
        raise(error)
      end
    end
  end
end
