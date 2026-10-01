# frozen_string_literal: true

module Live
  class Holder < LiveCable::Component
    reactive :count, -> { 0 }
    reactive :total, -> { 0 }, shared: true
    reactive :show, -> { true }
    reactive :broken, -> { false }

    actions :bump, :bump_total, :hide, :break_render

    def bump
      self.count += 1
    end

    def bump_total
      self.total += 1
    end

    def hide
      self.show = false
    end

    def break_render
      self.broken = true
    end
  end
end
