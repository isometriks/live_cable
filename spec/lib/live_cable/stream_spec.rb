# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LiveCable::Stream do
  let(:component) { Live::StreamFeed.new('unit') }

  def stream(initial = nil, dom_id: ->(row) { "row_#{row}" }, limit: nil)
    described_class.new(described_class::Declaration.new(:messages, initial, dom_id, limit), component)
  end

  describe '#initial_items' do
    it "returns the lambda's rows as an Array, giving the component to a lambda that takes it" do
      expect(stream(-> { 1..3 }).initial_items).to eq([1, 2, 3])
      expect(stream(->(feed) { [feed.title] }).initial_items).to eq(%w[Feed])
    end

    it 'gives the component to a lambda made from a Symbol, and to one with a splat' do
      component.define_singleton_method(:recent) { %w[one two] }

      expect(stream(lambda(&:recent)).initial_items).to eq(%w[one two])
      expect(stream(->(feed, *) { feed.recent }).initial_items).to eq(%w[one two])
    end

    it 'returns no rows without a lambda, or for a lambda that returns nil' do
      expect(stream.initial_items).to eq([])
      expect(stream(-> {}).initial_items).to eq([])
    end
  end

  describe '#take' do
    it 'returns the queued ops and leaves the stream empty, without a refill' do
      queue = stream
      queue.reset
      queue.insert(1)
      queue.update(2)

      expect(queue).to be_ops
      expect(queue.take).to eq([['a', 'row_1', 1], ['u', 'row_2', 2]])
      expect(queue).to have_attributes(ops: [], ops?: false, reset?: false, collapsed?: false)
    end
  end

  it 'has the declared name and limit' do
    expect(stream(limit: 50)).to have_attributes(name: :messages, limit: 50)
  end
end
