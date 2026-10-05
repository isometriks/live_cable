# frozen_string_literal: true

module LiveCable
  module ModelObserver
    include ObserverTracking

    def ==(other)
      super(other.is_a?(Delegator) ? other.__getobj__ : other)
    end
    alias eql? ==

    def _write_attribute(...)
      notify_live_cable_observers

      super
    end
  end
end
