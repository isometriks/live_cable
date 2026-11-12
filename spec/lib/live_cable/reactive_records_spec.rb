# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LiveCable::Container, 'with ActiveRecord records' do
  let(:owner_class) do
    stub_const('RecordOwner', Class.new(ActiveRecord::Base) { self.table_name = 'record_owners' })
  end

  let(:model_class) do
    owner_class
    stub_const('RecordTodo', Class.new(ActiveRecord::Base) do
      self.table_name = 'record_todos'
      belongs_to :owner, class_name: 'RecordOwner', optional: true
    end)
  end

  let(:container) { described_class.new }
  let(:a) { model_class.create!(title: 'a') }
  let(:b) { model_class.create!(title: 'b') }

  before do
    ActiveRecord::Schema.define do
      suppress_messages do
        create_table(:record_owners, force: true) { |t| t.string :name }
        create_table :record_todos, force: true do |t|
          t.string :title
          t.references :owner
        end
      end
    end

    container[:todos] = [a, b]
    container[:owner] = owner_class.create!(name: 'o')
    container.reset_changeset
  end

  let(:todos) { container[:todos] }
  let(:found) { todos.find { |todo| todo.title == 'a' } }

  it 'stores a record as itself' do
    expect(container[:owner]).to be_an_instance_of(owner_class)
  end

  it 'reads a record from a collection as itself' do
    expect([todos.first, found, todos[0], todos.each.first]).to all(be(a))
    expect(found).to be_an_instance_of(model_class)
    expect(case found when model_class then true end).to be true
  end

  it 'reads a record from a Hash as itself' do
    container[:by_title] = { 'a' => a }

    expect(container[:by_title]['a']).to be(a)
    expect(container[:by_title].fetch('a')).to be(a)
  end

  it 'marks the collection when a record read from it is written' do
    found.title = 'z'

    expect(container.changeset).to eq([:todos])
  end

  it 'keeps marking the collection when a record read from it is written after it was taken out' do
    record = found
    todos.delete(record)
    container.reset_changeset

    record.title = 'z'

    expect(container.changeset).to eq([:todos])
  end

  it 'queries and assigns associations with a reactive record' do
    owner = container[:owner]

    found.update!(owner:)

    expect(model_class.where(owner:).pluck(:title)).to eq(%w[a])
    expect(found.owner).to be(owner)
  end

  it 'compares two reads of the same record as equal' do
    expect(todos.first == found).to be true
    expect(todos.first).to eql(found)
  end

  it 'deletes a record from the collection it came from' do
    todos.delete(found)

    expect(todos.map(&:title)).to eq(%w[b])
  end

  it 'deletes a record read from a collection from a plain Array' do
    plain = todos.to_a.dup

    plain.delete(found)

    expect(plain.map(&:title)).to eq(%w[b])
  end

  it 'finds a record with include?, index and -' do
    expect(todos.include?(found)).to be true
    expect(todos.index(found)).to eq(0)
    expect((todos - [found]).map(&:title)).to eq(%w[b])
  end

  it 'still treats different unsaved records as unequal' do
    container[:drafts] = [model_class.new, model_class.new]
    drafts = container[:drafts]

    expect(drafts.first == drafts.last).to be false
  end
end
