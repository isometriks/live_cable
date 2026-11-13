# frozen_string_literal: true

module Live
  class DefaultReader < LiveCable::Component
    reactive :user_id, ->(c) { c.defaults[:owner_id] }
  end
end
