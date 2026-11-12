# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Collection streams', type: :system, js: true do
  def message_css(id) = "#message-#{id}"

  def bodies = all('[data-testid="message"] [data-testid="body"]').map(&:text)

  # The page reports subscribed before stream_from's subscription is live, so
  # a broadcast is published again until the page shows it. Each payload is
  # idempotent: inserting a row the page holds replaces it where it is.
  def publish_until(event, id, &shown)
    10.times do
      ChatStore.publish(event, id)
      return if shown.call
    end

    raise "the page never showed #{event} #{id}"
  end

  def root_js = "document.querySelector('[data-live-id-value=\"lobby\"]')"

  # A morph of the whole component takes the marker off its root again
  def mark_root = page.execute_script("#{root_js}.dataset.marked = 'yes'")

  def root_marked? = page.evaluate_script("#{root_js}.dataset.marked") == 'yes'

  def call_from_page(path)
    page.evaluate_async_script(<<~JS, path)
      const [path, done] = arguments
      fetch(path).then(() => done())
    JS
  end

  before do
    ChatStore.reset!
    ChatStore.add('First')
    ChatStore.add('Second')

    visit '/chat'
    expect(page).to have_css('[data-live-id-value="lobby"][data-live-status-value="subscribed"]')
  end

  it 'appends a broadcast message once, leaving the rest of the page as it was, and keeps the rows through a morph' do
    page.execute_script("document.getElementById('message-1').expando = 'kept'")
    find('[data-testid="draft"]').send_keys('half a thought')
    mark_root

    third = ChatStore.add('Third')
    publish_until('created', third.id) { page.has_css?(message_css(third.id), wait: 1) }

    expect(bodies).to eq(%w[First Second Third])
    expect(page).to have_css(message_css(third.id), count: 1)
    expect(page.evaluate_script("document.getElementById('message-1').expando")).to eq('kept')
    expect(page).to have_field('draft', with: 'half a thought')
    expect(root_marked?).to be(true)

    find('[data-testid="rename-input"]').fill_in(with: 'Garden')
    click_button 'Rename'

    expect(page).to have_css('[data-testid="room-name"]', text: 'Garden')
    expect(root_marked?).to be(false)
    expect(bodies).to eq(%w[First Second Third])
  end

  it 'updates and deletes rows in place, and runs the actions of a row that arrived by op' do
    third = ChatStore.add('Third')
    publish_until('created', third.id) { page.has_css?(message_css(third.id), wait: 1) }
    page.execute_script("document.getElementById('message-#{third.id}').expando = 'kept'")

    within(message_css(third.id)) { click_button 'Like (0)' }

    within(message_css(third.id)) do
      expect(page).to have_button('Like (1)')
      expect(page).to have_no_css('[live-loading], [disabled]')
    end
    expect(page.evaluate_script("document.getElementById('message-#{third.id}').expando")).to eq('kept')

    within(message_css(1)) { find('[data-testid="note"]').send_keys('remember this') }
    ChatStore.like(1)

    within(message_css(1)) do
      expect(page).to have_button('Like (1)')
      expect(page).to have_field('note', with: 'remember this')
    end

    ChatStore.delete(2)

    expect(page).to have_no_css(message_css(2))
    expect(bodies).to eq(%w[First Third])
  end

  it 'keeps focus and what was typed in a row through a frame that prepends a row and renames the room' do
    find("#{message_css(2)} [data-testid='note']").send_keys('half a note')

    notice = ChatStore.add('Notice', publish: false)
    publish_until('announced', notice.id) { page.has_css?(message_css(notice.id), wait: 1) }

    expect(page).to have_css('[data-testid="room-name"]', text: 'Announcements')
    expect(bodies).to eq(%w[Notice First Second])
    expect(page.evaluate_script('document.activeElement.closest("li")?.id')).to eq('message-2')
    expect(find("#{message_css(2)} [data-testid='note']").value).to eq('half a note')
  end

  it 'shows what it was never sent once it subscribes again' do
    third = ChatStore.add('Third', publish: false)
    ChatStore.delete(1, publish: false)

    call_from_page('/disconnect_sockets')
    expect(page).to have_css('[data-live-id-value="lobby"][data-live-status-value="disconnected"]', wait: 10)
    expect(page).to have_css('[data-live-id-value="lobby"][data-live-status-value="subscribed"]', wait: 20)
    expect(page).to have_css(message_css(third.id), count: 1)
    expect(page).to have_no_css(message_css(1))
    expect(bodies).to eq(%w[Second Third])
  end

  it 'refills the list from the stream when it is shown again, with what arrived while it was hidden' do
    click_button 'Hide messages'
    expect(page).to have_css('[data-testid="hidden"]')

    third = ChatStore.add('Third')
    ChatStore.publish('created', third.id)

    click_button 'Show messages'

    expect(page).to have_css(message_css(third.id), count: 1)
    expect(bodies).to eq(%w[First Second Third])
  end
end
