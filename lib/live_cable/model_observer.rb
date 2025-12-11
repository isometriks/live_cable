# frozen_string_literal: true

module LiveCable
  module ModelObserver
    include ObserverTracking

    def _write_attribute(...)
      notify_live_cable_observers

      super
    end
  end
end
