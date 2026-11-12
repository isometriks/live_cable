# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'A collection stream with a limit and no initial rows', type: :system, js: true do
  def root_js = "document.querySelector('[data-live-id-value=\"ticker\"]')"

  # A morph of the whole component takes the marker off its root again
  def mark_root = page.execute_script("#{root_js}.dataset.marked = 'yes'")

  def root_marked? = page.evaluate_script("#{root_js}.dataset.marked") == 'yes'

  def container_html = page.evaluate_script("document.querySelector('[data-testid=\"ticks\"]').innerHTML")

  # Each frame applies all of its ops at once, so once the page holds these
  # rows it holds them in their final order
  def expect_ticks(*ids)
    expect(page).to have_css('[data-testid="tick"]', count: ids.size)
    ids.each { |id| expect(page).to have_css("#tick-#{id}") }
    expect(all('[data-testid="tick"]').map { |row| row[:id] }).to eq(ids.map { |id| "tick-#{id}" })
  end

  before do
    visit '/ticker'
    expect(page).to have_css('[data-live-id-value="ticker"][data-live-status-value="subscribed"]')
  end

  it 'fills from empty, prepends and trims to its limit row by row, and resets to the markup it started with' do
    empty = container_html
    mark_root
    find('[data-testid="note"]').send_keys('kept')

    click_button 'Push'
    expect_ticks(1)
    click_button 'Push'
    click_button 'Push first'
    expect_ticks(3, 1, 2)
    click_button 'Push'
    expect_ticks(1, 2, 4)
    click_button 'Push first'
    expect_ticks(5, 1, 2)

    expect(root_marked?).to be(true)
    expect(page).to have_field('note', with: 'kept')

    click_button 'Clear'
    expect_ticks
    expect(container_html).to eq(empty)

    click_button 'Push'
    expect_ticks(6)
  end

  it 'keeps its rows through a Turbo Drive visit and back, and applies the ops sent after each' do
    click_button 'Push'
    click_button 'Push'
    expect_ticks(1, 2)

    click_link 'Ticker again'
    expect(page).to have_current_path('/ticker?visit=1')
    expect_ticks(1, 2)
    click_button 'Push'
    expect_ticks(1, 2, 3)

    page.go_back
    expect(page).to have_current_path('/ticker')
    expect_ticks(1, 2, 3)
    click_button 'Push'
    expect_ticks(2, 3, 4)
  end
end
