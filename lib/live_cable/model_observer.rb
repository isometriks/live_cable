# frozen_string_literal: true

module LiveCable
  module ModelObserver
    include ObserverTracking

    # A clone shares the original's attributes, so writes through it change the original
    def initialize_clone(other, **)
      super
      @live_cable_observers = other.live_cable_observers
    end

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

    # Unchanged reloads stay quiet, so reloading to check a record before writing
    # doesn't re-render
    def reload(...)
      return super unless live_cable_watched?

      before = @attributes

      super.tap { notify_live_cable_observers if live_cable_reload_changed?(before) }
    end

    # Catches in-place changes to serialized and JSON attributes once saved
    def changes_applied(...)
      super.tap { notify_live_cable_observers if saved_changes? }
    end

    # Lets a child's props digest see that a record it was given was written
    def live_cable_writes
      @live_cable_writes || 0
    end

    private

    def live_cable_watched?
      @live_cable_observers&.each_value&.any?(&:any?)
    end

    # Compares the database's values first, so columns nobody read stay unloaded
    def live_cable_reload_changed?(before)
      before.keys != @attributes.keys || before.keys.any? do |name|
        old = before[name]
        fresh = @attributes[name]
        raw_changed = old.value_before_type_cast != fresh.value_before_type_cast

        (raw_changed || old.changed_in_place?) && old.value != fresh.value
      end
    end

    def notify_live_cable_observers
      @live_cable_writes = live_cable_writes + 1

      super
    end
  end
end
