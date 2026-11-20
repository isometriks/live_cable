# frozen_string_literal: true

module Live
  class FailingDisconnect < LiveCable::Component
    reactive :count, -> { 0 }

    before_disconnect { raise 'save_last_seen failed' }
  end
end
