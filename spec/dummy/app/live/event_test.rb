# frozen_string_literal: true

module Live
  class EventTest < LiveCable::Component
    reactive :items, -> { [] }

    actions :add_item, :ping, :ping_window

    # State change - event rides along with the _refresh broadcast
    def add_item
      items << "Item #{items.size + 1}"

      dispatch_event('event-test:item-added', count: items.size)
    end

    # No state change - event is broadcast on its own
    def ping
      dispatch_event('event-test:pinged')
    end

    def ping_window
      dispatch_event('event-test:window-pinged', window: true)
    end
  end
end
