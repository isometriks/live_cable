# frozen_string_literal: true

module Live
  class Panel < LiveCable::Component
    reactive :account, -> { 0 }
  end
end
