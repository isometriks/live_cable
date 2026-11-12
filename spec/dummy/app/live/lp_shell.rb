# frozen_string_literal: true

module Live
  class LpShell < LiveCable::Component
    reactive :heading, -> { 'Inbox' }

    actions :retitle

    def retitle = self.heading = 'Archive'
  end
end
