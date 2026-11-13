# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LiveCable::ModelObserver do
  let(:theme_class) do
    Class.new do
      attr_reader :name

      def initialize(name) = @name = name
    end
  end

  let(:theme_coder) do
    theme_class = self.theme_class

    Class.new do
      define_singleton_method(:dump) { |theme| theme&.name }

      define_singleton_method(:load) do |name|
        raise ArgumentError, 'unreadable theme' if name == 'unreadable'

        name && theme_class.new(name)
      end
    end
  end

  let(:model_class) do
    coder = theme_coder

    Class.new(ActiveRecord::Base) do
      self.table_name = 'tracked_todos'
      include LiveCable::ModelObserver

      serialize :theme, coder: coder
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
          t.text :theme
          t.timestamps
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
      'a reload that brings in a change' => lambda { |todo|
        LiveCable::Delegator.unwrap(todo).class.where(id: todo.id).update_all(title: 'b')
        todo.reload
      },
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

    it 'does not mark the variable when a reload brings in nothing new' do
      todo.reload

      expect(container.changed?).to be false
    end

    it 'does not mark the variable when a reload after a save brings in nothing new' do
      todo.update!(title: 'b', done: true, settings: { 'theme' => 'dark' }, theme: theme_class.new('dark'))
      container.reset_changeset

      todo.reload

      expect(container.changed?).to be false
    end

    it 'does not mark the variable when a reload brings back an equal serialized value' do
      todo.update!(theme: theme_class.new('dark'))
      todo.reload.theme
      container.reset_changeset

      todo.reload

      expect(container.changed?).to be false
    end

    it 'marks the variable when a clone of the record is written' do
      LiveCable::Delegator.unwrap(todo).clone.title = 'b'

      expect(container.changeset).to eq([:todo])
    end

    it 'marks the variable when a reload discards an unsaved in-place edit' do
      todo.settings['theme'] = 'dark'

      todo.reload

      expect(container.changeset).to eq([:todo])
    end
  end

  describe 'reloading a record with a column nobody reads' do
    let(:id) { model_class.create!(title: 'a').id }

    before { model_class.connection.execute("UPDATE tracked_todos SET theme = 'unreadable' WHERE id = #{id}") }

    it 'does not load the column for a record no variable holds' do
      todo = model_class.find(id)

      expect { todo.reload }.not_to raise_error
    end

    it 'does not load the column for a record held in a variable' do
      todo = track(:todo, model_class.find(id))

      expect { todo.reload }.not_to raise_error
    end

    it 'does not load the column for a record in a reactive collection' do
      todos = track(:todos, [model_class.find(id)])

      expect { todos.first.reload }.not_to raise_error
      expect(container.changed?).to be false
    end

    it 'does not compare columns for a copy made during a call through a collection' do
      todos = track(:todos, [model_class.find(id)])
      todos.first.__getobj__.define_singleton_method(:copy) { clone }
      copy = todos.first.copy
      model_class.connection.execute("UPDATE tracked_todos SET theme = 'dark' WHERE id = #{id}")

      expect { copy.reload }.not_to raise_error
    end
  end

  describe 'models inside a collection' do
    let!(:todos) { track(:todos, [model_class.create!(title: 'a'), model_class.create!(title: 'b')]) }

    {
      'first.title=' => ->(todos) { todos.first.title = 'z' },
      'each { done= }' => ->(todos) { todos.each { |todo| todo.done = true } },
      'find.toggle!' => ->(todos) { todos.find { |todo| todo.title == 'a' }.toggle!(:done) },
      '[0].update!' => ->(todos) { todos[0].update!(title: 'z') },
      'last.reload after a change elsewhere' => lambda { |todos|
        LiveCable::Delegator.unwrap(todos.last).class.where(id: todos.last.id).update_all(title: 'y')
        todos.last.reload
      },
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

    it 'does not mark the collection when a reload brings in nothing new' do
      todos.last.reload

      expect(container.changed?).to be false
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

    it 'marks the collection when a clone of one of its models is written' do
      todos.first.clone.title = 'z'

      expect(container.changeset).to eq([:todos])
    end

    it 'does not mark the collection when a dup of one of its models is written' do
      todos.first.dup.title = 'z'

      expect(container.changed?).to be false
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
