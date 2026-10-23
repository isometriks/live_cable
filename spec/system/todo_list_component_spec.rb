# frozen_string_literal: true

require 'rails_helper'

# The todo list's markup is almost all control blocks, so every update here
# arrives as a structured part (a diff against the node the client holds)
# rather than as HTML.
RSpec.describe 'Todo List Component', type: :system, js: true do
  def titles
    all('[data-testid="title"]').map(&:text)
  end

  def add(title)
    count = all('[data-testid="todo"]').size
    find('[data-testid="new-title"]').fill_in(with: title)
    within('[data-testid="add-form"]') { click_button 'Add' }
    expect(page).to have_css('[data-testid="todo"]', count: count + 1)
  end

  before do
    visit '/todo_list'
    expect(page).to have_css('[data-live-status-value="subscribed"]')
  end

  it 'shows the empty state' do
    expect(page).to have_css('[data-testid="empty"]', text: 'Nothing to do.')
  end

  it 'adds todos newest first' do
    add('Milk')
    add('Eggs')

    expect(titles).to eq(%w[Eggs Milk])
    expect(page).to have_css('[data-testid="remaining"]', text: '2 left')
  end

  it 'moves a toggled todo into its done branch' do
    add('Milk')
    add('Eggs')

    find('#todo-2 input[type="checkbox"]').click

    expect(page).to have_css('#todo-2 .line-through', text: 'Eggs')
    expect(page).to have_css('[data-testid="remaining"]', text: '1 left')
  end

  it 'filters, removes and clears todos' do
    add('Milk')
    add('Eggs')
    add('Bread')
    find('#todo-2 input[type="checkbox"]').click
    expect(page).to have_css('#todo-2 .line-through')

    find('button[live-key="active"]').click
    expect(page).to have_css('[data-testid="todo"]', count: 2)
    expect(titles).to eq(%w[Bread Milk])

    find('button[live-key="all"]').click
    expect(page).to have_css('[data-testid="todo"]', count: 3)

    find('#todo-3 button', text: 'Remove').click
    expect(page).to have_no_css('#todo-3')

    click_button 'Clear completed'
    expect(page).to have_css('[data-testid="todo"]', count: 1)
    expect(titles).to eq(%w[Milk])
  end

  it 'keeps the DOM node of a row that did not change' do
    add('Milk')
    page.execute_script("window.keptRow = document.querySelector('#todo-1')")

    add('Eggs')
    find('#todo-2 input[type="checkbox"]').click
    expect(page).to have_css('#todo-2 .line-through')

    expect(page.evaluate_script("window.keptRow === document.querySelector('#todo-1')")).to be(true)
  end

  it 'goes back to the empty state when the last todo is removed' do
    add('Milk')

    find('#todo-1 button', text: 'Remove').click

    expect(page).to have_css('[data-testid="empty"]')
  end
end
