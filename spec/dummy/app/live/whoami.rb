# frozen_string_literal: true

module Live
  class Whoami < LiveCable::Component
    # current_user comes from the socket's identifiers, so a prerender has none
    def user_name
      respond_to?(:current_user) ? current_user : 'nobody'
    end
  end
end
