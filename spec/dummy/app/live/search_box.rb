# frozen_string_literal: true

module Live
  class SearchBox < LiveCable::Component
    reactive :query, -> { '' }, shared: true, writable: true
  end
end
