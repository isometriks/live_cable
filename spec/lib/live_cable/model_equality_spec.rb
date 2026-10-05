# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LiveCable::Delegator, 'ActiveRecord equality' do
  let(:model_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = 'equality_todos'
      include LiveCable::ModelObserver
    end
  end

  let(:container) { LiveCable::Container.new }

  before do
    ActiveRecord::Schema.define do
      suppress_messages do
        create_table :equality_todos, force: true do |t|
          t.string :title
        end
      end
    end

    container[:todos] = [model_class.create!(title: 'a'), model_class.create!(title: 'b')]
  end

  let(:todos) { container[:todos] }
  let(:found) { todos.find { |todo| todo.title == 'a' } }

  it 'compares two reads of the same record as equal' do
    expect(todos.first == found).to be true
    expect(todos.first != found).to be false
    expect(todos.first).to eql(found)
  end

  it 'compares a raw record with a wrapped one as equal' do
    raw = todos.__getobj__.first

    expect(raw == found).to be true
    expect(raw).to eql(found)
  end

  it 'deletes a wrapped record from the collection it came from' do
    todos.delete(found)

    expect(todos.map(&:title)).to eq(%w[b])
  end

  it 'deletes a wrapped record from a plain Array' do
    plain = todos.to_a.dup

    plain.delete(found)

    expect(plain.map(&:title)).to eq(%w[b])
  end

  it 'finds a wrapped record with include? and index' do
    expect(todos.include?(found)).to be true
    expect(todos.index(found)).to eq(0)
  end

  it 'removes a wrapped record with -' do
    expect((todos - [found]).map(&:title)).to eq(%w[b])
  end

  it 'still treats different unsaved records as unequal' do
    container[:drafts] = [model_class.new, model_class.new]
    drafts = container[:drafts]

    expect(drafts.first == drafts.last).to be false
    expect(drafts.__getobj__.first == drafts.last).to be false
  end
end
