# frozen_string_literal: true

module KernelCardHelper
  def trap(title, &)
    render(layout: 'shared/card', locals: { title: }, &)
  end
end
