# frozen_string_literal: true

module Live
  class FailingInitial < LiveCable::Component
    reactive :value, -> { raise 'initial value failed' }
  end
end
