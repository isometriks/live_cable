# frozen_string_literal: true

module Live
  class NumberedList < LiveCable::Component
    reactive :items, -> { [{ name: 'a' }] }

    actions :add, :number

    def add
      items << { name: 'b' }
    end

    def number
      items.each.with_index(1) { |item, position| item[:name] = "#{item[:name]}#{position}" }
    end
  end
end
