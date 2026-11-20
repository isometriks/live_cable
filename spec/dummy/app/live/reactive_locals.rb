# frozen_string_literal: true

module Live
  class ReactiveLocals < LiveCable::Component
    compound

    reactive :tmpl, -> { 'self_assign' }
    reactive :items, -> { %w[b c a] }
    reactive :count, -> { 1 }
    reactive :nickname, -> { 'Ann' }
    reactive :flag, -> { false }
    reactive :hidden, -> { 0 }
    reactive :display, -> { 'compact' }
    reactive :label, -> { 'plain' }
    reactive :rows, -> { [1, 2, 3] }
    reactive :total, -> { 100 }
    reactive :other, -> { 0 }

    actions :add_item, :bump, :clear_nickname, :toggle, :bump_hidden, :widen, :relabel, :add_row, :bump_other

    def add_item
      items << 'ab'
    end

    def bump
      self.count += 1
    end

    def clear_nickname
      self.nickname = nil
    end

    def toggle
      self.flag = !flag
    end

    def bump_hidden
      self.hidden += 1
    end

    def widen
      self.display = 'wide'
    end

    def relabel
      self.label = 'fancy'
    end

    def add_row
      rows << 4
    end

    def bump_other
      self.other += 1
    end

    def variant
      tmpl
    end

    def shout
      'from a method'
    end
  end
end
