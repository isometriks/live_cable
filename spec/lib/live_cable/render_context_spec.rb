# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LiveCable::RenderContext do
  let(:render_context) { described_class.new(nil) }
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
    render_context.unwrap(container[:owner])
    todo = render_context.unwrap(container[:todos]).first

    render_context.track(todo)[:tags] << 'ruby'

    expect(container.changeset).to eq([:todos])
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
end
