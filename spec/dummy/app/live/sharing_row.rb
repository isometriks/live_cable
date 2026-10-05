# frozen_string_literal: true

module Live
  class SharingRow < LiveCable::Component
    reactive :todo, -> { {} }

    actions :finish

    def finish
      todo[:done] = true
    end
  end
end
