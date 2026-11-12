# frozen_string_literal: true

module Live
  class DoubledView < LiveCable::Component
    reactive :doubled, -> { 0 }, shared: true

    actions :noop

    def noop; end
  end
end
