# frozen_string_literal: true

module Live
  class ReceiverCalls < LiveCable::Component
    reactive :theme, -> { 'light' }
    reactive :open, -> { false }

    actions :restyle, :toggle

    def restyle
      self.theme = 'dark'
    end

    def toggle
      self.open = !open
    end
  end
end
