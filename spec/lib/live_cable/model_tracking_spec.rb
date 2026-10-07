# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LiveCable::ModelObserver do
  let(:model_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = 'tracked_todos'
      include LiveCable::ModelObserver
    end
  end

  let(:container) { LiveCable::Container.new }

  before do
    ActiveRecord::Schema.define do
      suppress_messages do
        create_table :tracked_todos, force: true do |t|
          t.string :title
          t.boolean :done, default: false, null: false
          t.integer :points, default: 0, null: false
          t.json :settings, default: {}
        end
      end
    end
  end

  def track(variable, value)
    container[variable] = value
    container.reset_changeset
    container[variable]
  end

  describe 'a model held in a variable' do
    let(:todo) { track(:todo, model_class.create!(title: 'a')) }

    {
      '[]=' => ->(todo) { todo[:title] = 'b' },
      'write_attribute' => ->(todo) { todo.write_attribute(:title, 'b') },
      'increment!' => ->(todo) { todo.increment!(:points) },
      'toggle!' => ->(todo) { todo.toggle!(:done) },
      'update_column' => ->(todo) { todo.update_column(:title, 'b') },
      'update_columns' => ->(todo) { todo.update_columns(title: 'b') },
      'reload' => lambda(&:reload),
      'an in-place change that is saved' => ->(todo) { todo.tap { it.settings['theme'] = 'dark' }.save! },
    }.each do |write, perform|
      it "marks the variable dirty on #{write}" do
        perform.call(todo)

        expect(container.changeset).to eq([:todo])
      end
    end

    it 'does not mark the variable when a save changes nothing' do
      todo.save!

      expect(container.changed?).to be false
    end
  end

  describe 'models inside a collection' do
    let!(:todos) { track(:todos, [model_class.create!(title: 'a'), model_class.create!(title: 'b')]) }

    {
      'first.title=' => ->(todos) { todos.first.title = 'z' },
      'each { done= }' => ->(todos) { todos.each { |todo| todo.done = true } },
      'find.toggle!' => ->(todos) { todos.find { |todo| todo.title == 'a' }.toggle!(:done) },
      '[0].update!' => ->(todos) { todos[0].update!(title: 'z') },
      'last.reload' => ->(todos) { todos.last.reload },
    }.each do |write, perform|
      it "marks the collection dirty on #{write}" do
        perform.call(todos)

        expect(container.changeset).to eq([:todos])
      end
    end

    it 'marks a hash of models dirty when a value is written' do
      by_id = track(:by_id, todos.to_h { |todo| [todo.id, todo] })

      by_id[todos.first.id].title = 'z'

      expect(container.changeset).to include(:by_id)
    end

    it 'does not mark the collection when its models are only read' do
      todos.each(&:title)

      expect(container.changed?).to be false
    end

    it 'marks both variables when a record selected from the collection is written' do
      track(:selected, todos.first)

      todos.find { |todo| todo.title == 'a' }.title = 'z'

      expect(container.changeset).to contain_exactly(:todos, :selected)
    end
  end

  describe 'a replaced model' do
    it 'stops marking the variable when the old record is written' do
      old = model_class.create!(title: 'old')
      track(:todo, old)

      container[:todo] = model_class.create!(title: 'new')
      container.reset_changeset
      old.title = 'changed'

      expect(container.changed?).to be false
    end

    it 'stops marking the variable after cleanup' do
      todo = model_class.create!(title: 'a')
      track(:todo, todo)

      container.cleanup
      todo.title = 'changed'

      expect(todo.send(:live_cable_observers).values.flatten).to be_empty
    end
  end
end
