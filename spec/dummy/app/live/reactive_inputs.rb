# frozen_string_literal: true

module Live
  class ReactiveInputs < LiveCable::Component
    reactive :notify, -> { false }, writable: true
    reactive :tags, -> { [] }, writable: true
    reactive :size, -> { 's' }, writable: true
  end
end
