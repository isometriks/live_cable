# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Values moved between reactive variables' do
  include LiveCable::Testing

  it 're-renders the destination when a child changes an element moved into it' do
    board = live_mount('kanban_board')
    board.perform(:finish)

    card = live_mount(board.connection.get_component('kanban_card/card-1'), connection: board.connection)
    card.perform(:star)

    expect(board.rendered).to have_css('[data-testid="starred"]', text: '1')
  end
end
