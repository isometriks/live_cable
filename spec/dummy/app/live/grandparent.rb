# frozen_string_literal: true

module Live
  class Grandparent < LiveCable::Component
    reactive :title, -> { 'Family' }

    actions :rename

    def rename(params)
      self.title = params[:title]
    end
  end
end
