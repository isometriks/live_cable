# frozen_string_literal: true

module Live
  class StreamFeed < LiveCable::Component
    reactive :title, -> { 'Feed' }

    stream :messages

    actions :rename

    def rename(params)
      self.title = params[:title]
    end

    def heading = title
  end
end
