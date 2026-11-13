# frozen_string_literal: true

module Live
  class PropBoard < LiveCable::Component
    reactive :columns, -> { [{ id: 1, cards: PropCard.order(:id).to_a }] }
    reactive :cards, -> { PropCard.order(:id).to_a }

    actions :rename_nested, :rename_card

    def rename_nested
      columns.first[:cards].first.title = 'changed'
    end

    def rename_card
      cards.first.title = 'changed'
    end
  end
end
