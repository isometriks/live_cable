# frozen_string_literal: true

module Live
  class BlockLocalRead < LiveCable::Component
    reactive :names, -> { %w[ann bob] }
  end
end
