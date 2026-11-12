# frozen_string_literal: true

module Live
  class TagList < LiveCable::Component
    reactive :tags, -> { [] }

    actions :add

    def add(params)
      tags << { name: params[:name], hidden: params[:hidden].present? }
    end
  end
end
