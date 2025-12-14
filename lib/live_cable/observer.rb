module LiveCable
  class Observer
    def initialize(container)
      @container = container
    end

    def notify(variable)
      container.mark_dirty(variable)
    end

    private

    # @return [LiveCable::Container]
    attr_reader :container

    # @return [Symbol]
    attr_reader :variable
  end
end
