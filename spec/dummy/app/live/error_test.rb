# frozen_string_literal: true

module Live
  class ErrorTest < LiveCable::Component
    actions :trigger_error

    def trigger_error
      raise 'Something went wrong'
    end
  end
end
