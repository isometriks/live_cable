# frozen_string_literal: true

module Live
  class ReactiveInputs < LiveCable::Component
    reactive :notify, -> { false }, writable: true
    reactive :tags, -> { [] }, writable: true
    reactive :size, -> { 's' }, writable: true
    reactive :message, -> { '' }, writable: true
    reactive :sent, -> { [] }

    actions :send_message

    def send_message
      return if message.blank?

      sent << message
      self.message = ''
    end
  end
end
