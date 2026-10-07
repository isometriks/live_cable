# frozen_string_literal: true

module Live
  class HolderList < LiveCable::Component
    reactive :holders, -> { [0] }

    actions :add, :remove

    def add
      holders << holders.size
    end

    def remove
      holders.pop
    end
  end
end
