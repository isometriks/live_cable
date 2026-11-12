# frozen_string_literal: true

module Live
  class ConnectGate < LiveCable::Component
    reactive :count, -> { 0 }
    reactive :user, -> { '' }

    actions :increment

    before_connect :authorize!

    def increment
      self.count += 1
    end

    private

    def authorize!
      throw :abort if current_user == 'intruder'
      raise 'The gate is broken' if current_user == 'broken'

      self.user = current_user
    end
  end
end
