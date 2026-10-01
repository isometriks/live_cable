# frozen_string_literal: true

module Live
  class Todo < LiveCable::Component
    reactive :done, -> { [] }, shared: true

    actions :complete

    def complete
      done << id
    end
  end
end
