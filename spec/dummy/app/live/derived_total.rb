# frozen_string_literal: true

module Live
  class DerivedTotal < LiveCable::Component
    reactive :total, -> { 0 }, shared: true
    reactive :doubled, -> { 0 }, shared: true

    actions :bump, :noop

    before_render { self.doubled = total * 2 }

    def bump
      self.total += 1
    end

    def noop; end
  end
end
