# frozen_string_literal: true

module Live
  class Shell < LiveCable::Component
    reactive :account, -> { 0 }
  end
end
