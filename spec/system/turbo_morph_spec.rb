# frozen_string_literal: true

require 'rails_helper'

# Idiomorph morphs the page towards the HTTP prerender, which a throwaway
# instance renders from the initial state
RSpec.describe 'A Turbo morph over a live parent and the child it renders inline', type: :system, js: true do
  def bump(id, to:)
    click_button "increment-#{id}"
    expect(page).to have_css("[data-testid=\"count-#{id}\"]", text: to, wait: 5)
  end

  def morph(testid)
    before = find("[data-testid=\"#{testid}\"]").text
    yield
    expect(page).to have_no_css("[data-testid=\"#{testid}\"]", text: before, wait: 5)
  end

  def expect_kept
    expect(page).to have_css('[data-testid="count-morphed"]', text: '1')
    expect(page).to have_css('[data-testid="count-morphed-child"]', text: '1')
    expect(page).to have_selector('[data-live-status-value="subscribed"]', count: 2)

    bump('morphed-child', to: '2')

    expect(page).to have_css('[data-testid="count-morphed"]', text: '1')
  end

  before do
    visit '/turbo/morph'
    expect(page).to have_selector('[data-live-status-value="subscribed"]', count: 2, wait: 5)
    bump('morphed', to: '1')
    bump('morphed-child', to: '1')
  end

  it 'keeps them live, with their state, through a page refresh' do
    morph('rendered-at') { execute_script('Turbo.session.refresh(location.href)') }

    expect_kept
  end

  it 'keeps them live, with their state, through a Turbo Stream morph' do
    morph('item-rendered-at') { click_button 'Morph' }

    expect_kept
  end

  it 'builds them again from the new defaults of a page refresh that brings other ones' do
    morph('rendered-at') { execute_script("Turbo.visit('/turbo/morph?start=5', { action: 'replace' })") }

    expect(page).to have_css('[data-testid="count-morphed"]', text: '5')
    expect(page).to have_css('[data-testid="count-morphed-child"]', text: '0')
    expect(page).to have_selector('[data-live-status-value="subscribed"]', count: 2, wait: 5)

    bump('morphed-child', to: '1')

    expect(page).to have_css('[data-testid="count-morphed"]', text: '5')
  end

  it 'builds the parent again from the new defaults of a Turbo Stream morph that brings other ones' do
    morph('item-rendered-at') { click_button 'Morph to 5' }

    expect(page).to have_css('[data-testid="count-morphed"]', text: '5')
    expect(page).to have_selector('[data-testid="departing-morphed"][data-live-status-value="subscribed"]', wait: 5)

    bump('morphed', to: '6')
  end
end
