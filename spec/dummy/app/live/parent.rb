# frozen_string_literal: true

module Live
  class Parent < LiveCable::Component
    reactive :list, -> { [0] }

    actions :add

    def add
      list << list.size
    end
  end
end
