# frozen_string_literal: true

module Live
  module Streams
    # Live::EventTest as a collection stream: the event that follows an
    # insert fires once the row is on the page
    class EventFeed < LiveCable::Component
      Item = Data.define(:number)

      stream :items, dom_id: ->(item) { "item-#{item.number}" }

      actions :add_item

      def add_item
        item = Item.new(number: @added = (@added || 0) + 1)
        stream_insert(:items, item)
        dispatch_event('event-test:item-added', count: item.number)
      end
    end
  end
end
