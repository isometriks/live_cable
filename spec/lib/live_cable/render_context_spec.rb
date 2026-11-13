# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LiveCable::RenderContext do
  let(:component) { double('component', all_reactive_variables: [], shared_variables: []) }
  let(:render_context) { described_class.new(component) }
  let(:container) { LiveCable::Container.new }

  let(:model_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = 'render_context_owners'
    end
  end

  before do
    ActiveRecord::Schema.define do
      suppress_messages do
        create_table :render_context_owners, force: true do |t|
          t.string :name
        end
      end
    end

    container[:owner] = model_class.create!(name: 'a')
    container[:todos] = [{ id: 1, tags: [] }]
    container.reset_changeset
  end

  it 'returns the value inside a Delegator' do
    expect(render_context.unwrap(container[:todos])).to be(container[:todos].__getobj__)
  end

  it 'tracks an unwrapped value passed back in' do
    todos = render_context.unwrap(container[:todos])

    render_context.track(todos) << { id: 2 }

    expect(container.changeset).to eq([:todos])
  end

  it 'tracks a value nested inside an unwrapped one' do
    todo = render_context.unwrap(container[:todos]).first

    render_context.track(todo)[:tags] << 'ruby'

    expect(container.changeset).to eq([:todos])
  end

  it 'passes a record nested inside an unwrapped value as itself, tracked through its collection' do
    container[:owners] = [model_class.create!(name: 'b')]
    container.reset_changeset
    owner = render_context.unwrap(container[:owners]).first

    expect(render_context.track(owner)).to be(owner)

    owner.name = 'c'

    expect(container.changeset).to eq([:owners])
  end

  it 'tracks an element two variables hold through both' do
    container[:pinned] = [container[:todos].first]
    container.reset_changeset
    render_context.unwrap(container[:todos])
    todo = render_context.unwrap(container[:pinned]).first

    render_context.track(todo)[:tags] << 'ruby'

    expect(container.changeset).to contain_exactly(:todos, :pinned)
  end

  it 'gives back the wrapper a variable stores, though another variable holds its value' do
    container[:lists] = { all: container[:todos] }
    allow(component).to receive_messages(
      all_reactive_variables: %i[lists todos], lists: container[:lists], todos: container[:todos]
    )
    render_context.unwrap(container[:lists])
    todos = render_context.unwrap(container[:todos])

    expect(render_context.track(todos)).to be(container[:todos])
  end

  it 'tracks a collection built from an unwrapped one' do
    todos = render_context.unwrap(container[:todos])

    render_context.track(todos.reject { |todo| todo[:archived] }).first[:tags] << 'ruby'

    expect(container.changeset).to eq([:todos])
  end

  it 'tracks values from every variable a built collection holds' do
    other = LiveCable::Container.new
    other[:done] = [{ id: 2 }]
    todos = render_context.unwrap(container[:todos])
    done = render_context.unwrap(other[:done])

    render_context.track({ open: todos.dup, done: done.dup })[:done].first[:id] = 3

    expect([container.changeset, other.changeset]).to eq([[:todos], [:done]])
  end

  it 'leaves a built collection of plain values alone' do
    ids = render_context.unwrap(container[:todos]).map { |todo| todo[:id] }

    expect(render_context.track(ids)).to be(ids)
  end

  it 'leaves values it did not unwrap alone' do
    render_context.unwrap(container[:todos])
    other = [{ id: 3 }]

    expect(render_context.track(other)).to be(other)
    expect(render_context.track(42)).to eq(42)
  end

  describe '#prop_digest' do
    let(:owner) { container[:owner] }

    it 'changes when a record inside the collection is written to' do
      todos = [{ id: 1, owner: }]
      before = described_class.new(component).prop_digest(todos)

      owner.name = 'b'

      expect(described_class.new(component).prop_digest(todos)).not_to eq(before)
    end

    it 'walks each collection once per render' do
      todos = [{ id: 1 }]
      before = render_context.prop_digest(todos)
      todos.first[:id] = 2

      expect(render_context.prop_digest(LiveCable::Delegator.new(todos))).to eq(before)

      render_context.forget_tracked_values

      expect(render_context.prop_digest(todos)).not_to eq(before)
    end

    it 'skips values other than Arrays and Hashes' do
      expect(render_context.prop_digest(container[:owner])).to be_nil
      expect(render_context.prop_digest('a')).to be_nil
    end

    it 'digests a collection that holds itself' do
      todos = [{ id: 1 }]
      todos << todos

      expect(render_context.prop_digest(todos)).to be_an(Integer)
    end
  end
end
