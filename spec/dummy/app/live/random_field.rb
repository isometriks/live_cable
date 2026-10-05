# frozen_string_literal: true

module Live
  class RandomField < LiveCable::Component
    reactive :field_id, -> { "field-#{SecureRandom.hex(8)}" }
  end
end
