# frozen_string_literal: true

module Live
  class Digest < LiveCable::Component
    reactive :hash, -> { 'abc123' }
    reactive :count, -> { 0 }
    reactive :rows, -> { 2 }

    actions :increment, :drop_row

    def increment
      self.count += 1
      self.hash = "abc#{count}"
    end

    def drop_row
      self.rows -= 1
    end
  end
end
