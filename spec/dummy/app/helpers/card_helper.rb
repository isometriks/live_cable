# frozen_string_literal: true

module CardHelper
  def card(title, &)
    render(layout: 'shared/card', locals: { title: }, &)
  end

  def card_presenter
    CardPresenter.new(self)
  end
end
