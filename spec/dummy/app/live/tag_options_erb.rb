# frozen_string_literal: true

module Live
  class TagOptionsErb < LiveCable::Component
    reactive :classes, -> { %w[btn primary] }

    actions :add_class

    def add_class
      classes << 'more'
    end
  end
end
