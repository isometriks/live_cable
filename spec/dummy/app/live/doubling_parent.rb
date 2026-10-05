# frozen_string_literal: true

module Live
  class DoublingParent < LiveCable::Component
    reactive :amount, -> { 2 }, shared: true
    reactive :label, -> { 'a' }
    reactive :note, -> { '' }

    actions :relabel_and_add, :annotate, :explode

    def relabel_and_add
      self.label += 'b'
      self.amount += 10
    end

    def annotate
      self.note = 'noted'
    end

    def explode
      self.label += 'b'
      self.amount = -1
    end
  end
end
