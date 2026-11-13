# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Reactive values in ActiveRecord queries' do
  let(:model_class) do
    stub_const('QueryProduct', Class.new(ActiveRecord::Base) { self.table_name = 'query_products' })
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

  it 'matches reactive records in a plain array' do
    products = model_class.where(name: %w[a c]).map { |product| reactive(product) }

    expect(model_class.where(id: products).pluck(:name)).to contain_exactly('a', 'c')
  end

  it 'orders by a reactive array with in_order_of' do
    ids = reactive(model_class.where(name: %w[c a]).order(id: :desc).ids)

    expect(model_class.in_order_of(:id, ids).pluck(:name)).to eq(%w[c a])
  end

  it 'matches a reactive array in Arel predicates' do
    ids = reactive(model_class.where(name: %w[a c]).ids)
    column = model_class.arel_table[:id]

    expect(model_class.where(column.in(ids)).pluck(:name)).to contain_exactly('a', 'c')
    expect(model_class.where(column.not_in(ids)).pluck(:name)).to eq(%w[b])
  end

  it 'leaves relations marshalable, as Rails.cache needs' do
    relation = model_class.where(name: 'a')

    expect(Marshal.load(Marshal.dump(relation)).pluck(:name)).to eq(%w[a])
    expect(Marshal.load(Marshal.dump(relation.load)).map(&:name)).to eq(%w[a])
  end

  describe 'reactive ids passed to finders and bulk methods' do
    let(:ids) { model_class.order(:id).ids }

    it 'finds every id, and raises for a missing one' do
      expect(model_class.find(reactive(ids.last(2))).map(&:name)).to eq(%w[b c])
      expect(model_class.all.find(reactive(ids.last(2))).map(&:name)).to eq(%w[b c])
      expect { model_class.all.find(reactive([ids.first, 0])) }.to raise_error(ActiveRecord::RecordNotFound)
      expect(model_class.all.find(reactive([]))).to eq([])
    end

    it "leaves an association's destroy working after a relation's destroy" do
      owner_class = stub_const('IdsOwner', Class.new(ActiveRecord::Base) { self.table_name = 'ids_owners' })
      owner_class.has_many :products, class_name: 'QueryProduct', foreign_key: :owner_id
      ActiveRecord::Schema.define do
        suppress_messages do
          create_table(:ids_owners, force: true)
          add_column :query_products, :owner_id, :integer
        end
      end
      model_class.reset_column_information
      owner = owner_class.create!
      first, second = Array.new(2) { owner.products.create!(name: 'x') }

      model_class.where(owner_id: owner.id).destroy(second.id)

      expect { owner.products.destroy(first) }.not_to raise_error
      expect(owner.products.reload.count).to eq(0)
    end

    it 'destroys every record' do
      model_class.destroy(reactive(ids.last(2)))

      expect(model_class.pluck(:name)).to eq(%w[a])
    end

    it 'deletes every record' do
      expect(model_class.delete(reactive(ids.last(2)))).to eq(2)
      expect(model_class.delete(reactive([]))).to eq(0)
      expect(model_class.pluck(:name)).to eq(%w[a])
    end

    it 'updates every record' do
      model_class.update(reactive(ids.last(2)), [{ name: 'x' }, { name: 'y' }])
      model_class.all.update!(reactive([ids.first]), [{ name: 'z' }])

      expect(model_class.order(:id).pluck(:name)).to eq(%w[z x y])
    end
  end

  describe 'a polymorphic association' do
    let(:note_class) do
      Class.new(ActiveRecord::Base) do
        self.table_name = 'query_notes'
        belongs_to :subject, polymorphic: true
      end
    end

    let(:author_class) { Class.new(ActiveRecord::Base) { self.table_name = 'query_authors' } }

    before do
      ActiveRecord::Schema.define do
        suppress_messages do
          create_table :query_authors, force: true
          create_table :query_notes, force: true do |t|
            t.string :subject_type
            t.integer :subject_id
            t.string :body
          end
        end
      end

      stub_const('QueryAuthor', author_class)
      note_class.create!(subject: QueryProduct.first, body: 'on product')
      note_class.create!(subject: QueryAuthor.create!, body: 'on author')
    end

    it 'matches only rows of a reactive record' do
      product = reactive(QueryProduct.first)

      expect(note_class.where(subject: product).pluck(:body)).to eq(['on product'])
      expect(note_class.where.not(subject: product).pluck(:body)).to eq(['on author'])
    end

    it 'matches only rows of the records in a reactive array' do
      expect(note_class.where(subject: reactive([QueryProduct.first])).pluck(:body)).to eq(['on product'])
    end

    it 'matches only rows of the reactive records in a plain array' do
      expect(note_class.where(subject: [reactive(QueryProduct.first)]).pluck(:body)).to eq(['on product'])
    end
  end
end
