# frozen_string_literal: true

module Live
  # Declares the authorization hook once, as an ApplicationComponent would
  class GuardedBase < LiveCable::Component
    class Refused < StandardError; end

    reactive :mode, -> { 'open' }
    reactive :notice, -> { '' }

    before_dispatch :authorize!

    rescue_from Refused do
      self.notice = 'refused'
    end

    def dispatches
      @dispatches ||= []
    end

    private

    def authorize!
      dispatches << current_dispatch

      case mode
      when 'abort' then throw :abort
      when 'raise' then raise Refused
      end
    end
  end
end
