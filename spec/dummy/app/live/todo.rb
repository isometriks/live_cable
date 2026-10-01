# frozen_string_literal: true

module Live
  class Todo < LiveCable::Component
    reactive :done, -> { [] }, shared: true
    reactive :starred, shared: true

    actions :complete, :complete_and_announce, :slow_complete, :star

    def complete
      done << id
    end

    def complete_and_announce
      complete
      dispatch_event('todo:completed', id:)
    end

    def slow_complete
      sleep 0.5
      complete
    end

    # Only the list shows it
    def star
      self.starred = id
    end
  end
end
