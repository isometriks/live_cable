# frozen_string_literal: true

module Live
  class Loading < LiveCable::Component
    reactive :count, -> { 0 }
    reactive :title, -> { '' }

    actions :slow_increment, :slow_noop, :save

    def slow_increment
      sleep 0.5
      self.count += 1
    end

    # Changes nothing - the client's loading state is cleared by the _ack
    def slow_noop
      sleep 0.5
    end

    def save(params)
      sleep 0.5
      self.title = params[:title]
    end
  end
end
