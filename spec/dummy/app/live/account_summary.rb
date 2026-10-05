# frozen_string_literal: true

module Live
  class AccountSummary < LiveCable::Component
    reactive :account_id, -> { 1 }, shared: true
  end
end
