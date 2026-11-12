# frozen_string_literal: true

module LiveCable
  # A page whose JavaScript can't apply collection stream ops subscribed to
  # a component that declares streams, as a tab left open across a deploy
  # does. It is shown a reload box and never reported.
  class OutdatedClient < Error
    def initialize(message = 'This page is out of date. Reload to continue.')
      super
    end
  end
end
