# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Child components inside table and select markup', type: :system, js: true do
  before do
    visit '/table_rows'
    expect(page).to have_selector('[data-live-id-value="table-rows"][data-live-status-value="subscribed"]', wait: 5)
  end

  it 'keeps child rows inside the table and child options inside the select' do
    expect(page).to have_css('[data-testid="rows-table"] > tbody > tr.live-row', count: 2)
    expect(page).to have_css('[data-testid="rows-select"] > option', count: 2)
    execute_script("document.querySelector('[data-testid=\"pinned-row\"] td').textContent = 'kept'")

    click_button 'Add row'

    expect(page).to have_css('[data-testid="row-count"]', text: '3')
    expect(page).to have_css('[data-testid="rows-table"] > tbody > tr.live-row', count: 3)
    expect(page).to have_css('[data-testid="rows-select"] > option', count: 3)
    expect(page).to have_css('[data-testid="rows-table"] tr:first-child', text: 'kept')
    expect(page).to have_no_css('[data-live-id-value="table-rows"] > tr')
  end

  it 'places a child whose id the placeholder escapes' do
    expect(page).to have_css('[data-testid="quoted-tags"] > [data-testid="tag"]', exact_text: 'a & "b"')

    click_button 'Add row'

    expect(page).to have_css('[data-testid="row-count"]', text: '3')
    expect(page).to have_css('[data-testid="quoted-tags"] > [data-testid="tag"]', exact_text: 'a & "b"')
  end
end
