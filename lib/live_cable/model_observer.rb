module LiveCable
  module ModelObserver
    def _write_attribute(...)
      notify_live_cable_observers

      super
    end

    # @param observer [LiveCable::Observer]
    def add_live_cable_observer(observer, variable)
      observers = live_cable_observers_for(variable)

      unless observers.include?(observer)
        observers << observer
      end
    end

    private

    def live_cable_observers
      @live_cable_observers ||= {}
    end

    def live_cable_observers_for(variable)
      live_cable_observers[variable] ||= []
    end

    def notify_live_cable_observers
      live_cable_observers.each do |variable, observers|
        observers.each { |observer| observer.notify(variable) }
      end
    end
  end
end
