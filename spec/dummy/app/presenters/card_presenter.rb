# frozen_string_literal: true

class CardPresenter
  def initialize(view)
    @view = view
  end

  def card(title, &)
    @view.render(layout: 'shared/card', locals: { title: }, &)
  end
end
