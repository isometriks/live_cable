# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'A collection stream beside state that changes with it', type: :system, js: true do
  def broadcast_until_shown(id)
    10.times do
      ActionCable.server.broadcast('inbox', { id:, text: "Message #{id}" })
      return if page.has_css?("#message-#{id}", wait: 1)
    end

    raise "the page never showed message #{id}"
  end

  def open_first_row = page.execute_script("document.querySelector('#message-1 details').open = true")

  def first_row_open? = page.evaluate_script("document.querySelector('#message-1 details').open")

  it 'leaves the rows it already shows alone on a frame of only row ops' do
    visit '/inbox'
    expect(page).to have_css('[data-live-id-value="inbox"][data-live-status-value="subscribed"]')
    broadcast_until_shown(1)
    open_first_row

    broadcast_until_shown(2)

    expect(first_row_open?).to be(true)
  end

  it 'leaves the rows it already shows alone when an insert also changes another part' do
    visit '/inbox?counted=1'
    expect(page).to have_css('[data-live-id-value="inbox"][data-live-status-value="subscribed"]')
    broadcast_until_shown(1)
    open_first_row

    broadcast_until_shown(2)

    expect(page).to have_css('[data-testid="count"]', text: '2 messages')
    expect(first_row_open?).to be(true)
  end
end
