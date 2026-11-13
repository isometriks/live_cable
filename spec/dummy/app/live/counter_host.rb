# frozen_string_literal: true

module Live
  class CounterHost < LiveCable::Component
    reactive :title, -> { 'Counters' }

    actions :rename

    def rename
      self.title = 'Renamed'
    end
  end
end
