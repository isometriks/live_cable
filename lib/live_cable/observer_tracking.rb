# frozen_string_literal: true

module LiveCable
  module ObserverTracking
    # @param observer [LiveCable::Observer]
    # @param variable [Symbol]
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
      puts ""
      puts ""
      puts ">>>> NOTIFYING"
      puts live_cable_observers.inspect

      live_cable_observers.each do |variable, observers|
        puts observers.inspect
        observers.each { |observer| observer.notify(variable) }
      end
    end
  end
end
