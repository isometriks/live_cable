# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Typing while the server pushes a render', type: :system, js: true do
  before do
    visit '/chat_test'
  end

  { 'an input' => 'draft', 'a textarea' => 'note' }.each do |kind, name|
    it "keeps what was typed into #{kind} since the last send, and sends it" do
      find_field("#{name}-input").send_keys('hel')
      expect(page).to have_selector("[data-testid=\"#{name}\"]", text: 'hel', wait: 5)

      find_field("#{name}-input").send_keys('lo')
      ActionCable.server.broadcast(Live::ChatTest::STREAM_NAME, { text: 'Hi there' })

      expect(page).to have_selector('li', text: 'Hi there', wait: 5)
      expect(page).to have_field("#{name}-input", with: 'hello')
      expect(page).to have_selector("[data-testid=\"#{name}\"]", text: 'hello', wait: 5)
    end
  end

  it 'keeps what was typed while its own update was on its way, and sends it' do
    find_field('slow-draft-input').send_keys('hel')
    expect(page).to have_selector('[data-testid="slow-draft-input"][live-loading]', wait: 5)

    find_field('slow-draft-input').send_keys('lo')

    expect(page).to have_selector('[data-testid="slow-draft"]', text: 'hello', wait: 5)
    expect(page).to have_field('slow-draft-input', with: 'hello')
  end
end
