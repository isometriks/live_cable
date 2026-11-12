# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Switching rooms on a collection stream', type: :system, js: true do
  def texts = all('[data-testid="message"]').map(&:text)

  # The page reports subscribed before stream_from's subscription is live, so
  # a broadcast is sent again until the page shows it
  def broadcast_until_shown(room_id, message)
    10.times do
      RoomHistory.broadcast(room_id, message)
      return if page.has_css?("#message-#{message['id']}", wait: 1)
    end

    raise "the page never showed message #{message['id']}"
  end

  before do
    RoomHistory.reset!
    RoomHistory.add(1, 'one')
    RoomHistory.add(2, 'two')

    visit '/lobby'
    expect(page).to have_css('[data-live-id-value="lobby"][data-live-status-value="subscribed"]')
  end

  it "replaces the rows with the new room's, follows only its broadcasts, and refills on the way back" do
    broadcast_until_shown(1, RoomHistory.add(1, 'hello'))
    expect(texts).to eq(%w[one hello])

    click_button 'Room 2'

    expect(page).to have_css('[data-testid="room"]', text: 'Room 2')
    expect(texts).to eq(['two'])

    away = RoomHistory.add(1, 'while away')
    RoomHistory.broadcast(1, away)
    broadcast_until_shown(2, RoomHistory.add(2, 'welcome'))

    expect(page).to have_no_css("#message-#{away['id']}")
    expect(texts).to eq(%w[two welcome])

    click_button 'Room 1'

    expect(page).to have_css('[data-testid="room"]', text: 'Room 1')
    expect(texts).to eq(['one', 'hello', 'while away'])
  end
end
