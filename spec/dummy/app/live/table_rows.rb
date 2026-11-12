# frozen_string_literal: true

module Live
  class TableRows < LiveCable::Component
    reactive :rows, -> { [1, 2] }

    actions :add

    def add
      rows << (rows.max + 1)
    end
  end
end
