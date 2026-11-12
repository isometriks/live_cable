# frozen_string_literal: true

module LiveCable
  # Raised by Component#refuse! to stop a component the person may no longer
  # use. Never offered to rescue_from.
  class Refused < Error
    # @return [String, Symbol, nil] Sent to the client as live:refused's reason
    attr_reader :reason

    def initialize(reason = nil)
      @reason = reason
      super(reason ? "Refused: #{reason}" : 'Refused')
    end
  end
end
