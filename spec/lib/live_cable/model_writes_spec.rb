# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Writes to models held in reactive variables' do
  include LiveCable::Testing

  before do
    ActiveRecord::Schema.define do
      suppress_messages do
        create_table :record_todos, force: true do |t|
          t.boolean :done, default: false, null: false
        end
      end
    end

    stub_const('RecordTodo', Class.new(ActiveRecord::Base) { self.table_name = 'record_todos' })
    2.times { RecordTodo.create! }
  end

  it 're-renders after a write chained off reload on an element of a collection' do
    list = live_mount('record_list')

    list.perform(:finish_first)

    expect(list.rendered).to have_css('[data-testid="done"]', text: '1')
  end

  it 're-renders the parent when a child writes to the record it was passed after reloading it' do
    list = live_mount('record_list')
    row_id = "record_row/row-#{RecordTodo.first.id}"
    row = live_mount(list.connection.get_component(row_id), connection: list.connection)

    row.perform(:finish)

    expect(list.rendered).to have_css('[data-testid="done"]', text: '1')
  end
end
