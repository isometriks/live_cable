# frozen_string_literal: true

module Live
  class KernelNamesOverrides < LiveCable::Component
    reactive :method, -> { 'post' }

    def send(message)
      "sent #{message}"
    end

    def subtitle
      'sub'
    end
  end
end
