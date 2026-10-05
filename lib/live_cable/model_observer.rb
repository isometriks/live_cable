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

    def write_attribute(...)
      notify_live_cable_observers

      super
    end

    def update_columns(...)
      super.tap { notify_live_cable_observers }
    end

    def reload(...)
      super.tap { notify_live_cable_observers }
    end

    # Catches in-place changes to serialized and JSON attributes once saved
    def changes_applied(...)
      super.tap { notify_live_cable_observers if saved_changes? }
    end

    # Lets a Delegator around this record see that a call it forwarded wrote to it
    def live_cable_writes
      @live_cable_writes || 0
    end

    private

    def notify_live_cable_observers
      @live_cable_writes = live_cable_writes + 1

      super
    end
  end
end
