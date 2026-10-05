# frozen_string_literal: true

module Live
  class TagOptions < LiveCable::Component
    reactive :classes, -> { %w[btn primary] }
    reactive :flags, -> { { active: true, hidden: false } }
    reactive :display, -> { %w[btn primary] }

    actions :add_class

    def add_class
      classes << 'more'
    end
  end
end
