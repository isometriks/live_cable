# frozen_string_literal: true

module Live
  class AccountSwitcher < LiveCable::Component
    reactive :account_id, -> { 1 }, shared: true, writable: true
  end
end
