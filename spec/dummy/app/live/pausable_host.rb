# frozen_string_literal: true

module Live
  class PausableHost < LiveCable::Component
    reactive :label, -> { 'a' }

    actions :relabel

    def relabel
      self.label += 'b'
    end
  end
end
