# frozen_string_literal: true

module Live
  class DigestRow < LiveCable::Component
    reactive :hash, -> { '' }
  end
end
