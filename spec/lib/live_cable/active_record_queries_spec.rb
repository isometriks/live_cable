# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Reactive values in ActiveRecord queries' do
  let(:model_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = 'query_products'
    end
  end

  before do
    ActiveRecord::Schema.define do
      suppress_messages do
        create_table :query_products, force: true do |t|
          t.string :name
        end
      end
    end

    %w[a b c].each { |name| model_class.create!(name:) }
  end

  def reactive(value)
    LiveCable::Container.new.tap { |container| container[:value] = value }[:value]
  end

  it 'matches the elements of a reactive array' do
    ids = reactive(model_class.order(:id).limit(2).ids)

    expect(model_class.where(id: ids).pluck(:name)).to contain_exactly('a', 'b')
    expect(model_class.where.not(id: ids).pluck(:name)).to eq(%w[c])
  end

  it 'matches a reactive array against a string column' do
    expect(model_class.where(name: reactive(%w[a c])).pluck(:name)).to contain_exactly('a', 'c')
  end

  it 'matches a derived reactive array' do
    names = reactive([{ name: 'b' }]).map { |product| product[:name] }

    expect(model_class.where(name: names).pluck(:name)).to eq(%w[b])
  end
end
