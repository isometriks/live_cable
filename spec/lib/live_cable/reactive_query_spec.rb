# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'reactive_query' do
  include LiveCable::Testing

  before do
    Chore.create_tables
    Chore.create!(name: 'Dishes', done: true)
    Chore.create!(name: 'Laundry')
    Chore.create!(name: 'Report', list: 'work')
  end

  def queries(&)
    sql = []
    callback = ->(*, payload) { sql << payload[:sql] unless payload[:name] == 'SCHEMA' }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &)
    sql
  end

  def aggregates(sql)
    sql.grep(/MAX\(/)
  end

  def chore_names(component)
    component.rendered.all('[data-testid="chore"]').map(&:text)
  end

  def refreshed_parts(component)
    component.broadcasts(:_refresh).map { |broadcast| broadcast[:_refresh][:p].compact }
  end

  def stored(component, name)
    component.connection.get(component.live_id, component.component, name, nil)
  end

  describe 'the reader' do
    it 'renders the block applied to the loaded relation' do
      list = live_mount('chore_list')

      expect(chore_names(list)).to eq(%w[Laundry Dishes])
      expect(list.rendered).to have_css('[data-testid="summary"]', text: '1 to do')
    end

    it 'loads the relation once per render, and fingerprints it from the loaded records' do
      sql = queries { live_mount('chore_list') }

      expect(sql.grep(/FROM "chores"/).size).to eq(1)
      expect(aggregates(sql)).to be_empty
    end

    it 'keeps only the fingerprint between renders' do
      list = live_mount('chore_list')
      relation = Chore.where(list: 'home').order(:id)

      expect(stored(list, :chores)).to have_attributes(
        version: relation.cache_key_with_version,
        digest: ActiveSupport::Digest.hexdigest(relation.to_sql)
      )
      expect(queries { list.chores }).not_to be_empty
    end

    it 'returns the loaded relation when there is no block' do
      component_class = Class.new(LiveCable::Component) do
        reactive_query :chores, -> { Chore.where(list: 'work') }
      end

      chores = component_class.new('plain').chores

      expect(chores).to be_a(ActiveRecord::Relation).and(be_loaded)
      expect(chores.map(&:name)).to eq(%w[Report])
    end

    it 'renders on the HTTP prerender' do
      html = Capybara.string(ApplicationController.render(inline: "<%= live('chore_list', id: 'prerendered') %>"))

      expect(html.all('[data-testid="chore"]').map(&:text)).to eq(%w[Laundry Dishes])
    end

    it 'raises when the lambda does not return a relation' do
      component_class = Class.new(LiveCable::Component) do
        reactive_query :chores, -> { Chore.all.to_a }
      end

      expect { component_class.new('array').chores }.to raise_error(LiveCable::Error, /ActiveRecord::Relation/)
    end

    it 'is not settable from the client' do
      list = live_mount('chore_list')

      expect { list.set_reactive(:chores, 'x') }.to raise_error(LiveCable::Forbidden)
    end
  end

  describe 'refresh' do
    it 'does not re-render when the result is unchanged' do
      list = live_mount('chore_list')
      list.clear_broadcasts

      sql = queries { list.receive_stream('chores', {}) }

      expect(list.broadcasts(:_refresh)).to be_empty
      expect(aggregates(sql).size).to eq(1)
    end

    it 'does not re-render an empty result that is still empty' do
      list = live_mount('chore_list', list: 'garage')
      list.clear_broadcasts

      list.receive_stream('chores', {})

      expect(list.broadcasts(:_refresh)).to be_empty
    end

    it 'does not re-render for a write outside the query' do
      list = live_mount('chore_list')
      list.clear_broadcasts

      Chore.create!(name: 'Invoices', list: 'work')
      list.receive_stream('chores', {})

      expect(list.broadcasts(:_refresh)).to be_empty
    end

    it 're-renders the parts that read the query after an insert' do
      list = live_mount('chore_list')
      list.clear_broadcasts

      Chore.create!(name: 'Garden')
      list.receive_stream('chores', { refresh: ['chores'] })

      expect(chore_names(list)).to eq(%w[Laundry Garden Dishes])
      expect(list.rendered).to have_css('[data-testid="summary"]', text: '2 to do')
      expect(refreshed_parts(list).join).not_to include('Chores')
    end

    it 're-renders after an edit' do
      list = live_mount('chore_list')

      Chore.find_by(name: 'Laundry').update!(name: 'Ironing')
      list.receive_stream('chores', {})

      expect(chore_names(list)).to eq(%w[Ironing Dishes])
    end

    it 're-renders after a delete' do
      list = live_mount('chore_list')

      Chore.find_by(name: 'Dishes').destroy!
      list.receive_stream('chores', {})

      expect(chore_names(list)).to eq(%w[Laundry])
    end

    it 're-renders after a write in an action' do
      list = live_mount('chore_list')

      list.perform(:add, name: 'Garden')

      expect(chore_names(list)).to eq(%w[Laundry Garden Dishes])
    end

    it 'misses a write that skips updated_at, which dirty forces' do
      list = live_mount('chore_list')
      list.clear_broadcasts

      Chore.find_by(name: 'Laundry').update_columns(name: 'Ironing')
      list.receive_stream('chores', {})

      expect(list.broadcasts(:_refresh)).to be_empty

      sql = queries { list.receive_stream('chores', { dirty: true }) }

      expect(chore_names(list)).to eq(%w[Ironing Dishes])
      expect(aggregates(sql)).to be_empty
    end

    it 'raises for a name that is not a reactive_query' do
      list = live_mount('chore_list')

      expect { list.receive_stream('chores', { refresh: ['heading'] }) }.
        to raise_error(LiveCable::Error, /heading/)
    end

    it 'raises during a render' do
      list = live_mount('chore_list')
      allow(Chore).to receive(:where).and_wrap_original do |original, *args, **kwargs|
        list.component.refresh(:chores)
        original.call(*args, **kwargs)
      end

      expect { list.perform(:rename, heading: 'Jobs') }.to raise_error(LiveCable::Error, /render/)
    end
  end

  describe 'a change to the query itself' do
    it 're-renders the query without an aggregate query' do
      list = live_mount('chore_list')

      sql = queries { list.perform(:switch_list, list: 'work') }

      expect(chore_names(list)).to eq(%w[Report])
      expect(aggregates(sql)).to be_empty
    end

    it 'leaves the query alone when an unrelated variable changes' do
      list = live_mount('chore_list')
      list.clear_broadcasts

      sql = queries { list.perform(:rename, heading: 'Jobs') }

      expect(refreshed_parts(list)).to eq([['Jobs']])
      expect(sql).to be_empty
    end
  end

  describe 'queries Rails cannot fingerprint from their records' do
    before { Chore.find_by(name: 'Dishes').update!(person: Person.create!(name: 'Sam')) }

    it 'runs the aggregate query at render' do
      sql = queries { live_mount('chore_totals') }

      expect(aggregates(sql).size).to eq(3)
    end

    it 'stores the same fingerprint refresh computes' do
      totals = live_mount('chore_totals')
      totals.clear_broadcasts

      totals.receive_stream('chores', nil)

      expect(totals.broadcasts(:_refresh)).to be_empty
    end

    it 'refreshes every query when given no names' do
      totals = live_mount('chore_totals')

      Chore.create!(name: 'Garden', person: Person.first)
      totals.receive_stream('chores', nil)

      expect(totals.rendered).to have_css('[data-testid="open-count"]', text: '3 open')
      expect(totals.rendered.all('[data-testid="assigned"]').map(&:text)).to eq(['Dishes: Sam', 'Garden: Sam'])
      expect(totals.rendered).to have_css('[data-testid="names"]', text: 'Dishes, Laundry, Report, Garden')
    end
  end

  describe 'an association' do
    before { Chore.find_by(name: 'Dishes').update!(person: Person.create!(name: 'Sam')) }

    it 'shows rows added after the association loaded' do
      chores = live_mount('person_chores')

      Chore.create!(name: 'Garden', person: Person.first)
      chores.receive_stream('chores', {})

      expect(chore_names(chores)).to eq(%w[Dishes Garden])
    end

    it 'does not re-render when its rows are unchanged' do
      chores = live_mount('person_chores')
      chores.clear_broadcasts

      chores.receive_stream('chores', {})

      expect(chores.broadcasts(:_refresh)).to be_empty
    end

    it 'reloads it when dirty' do
      chores = live_mount('person_chores')

      Chore.create!(name: 'Garden', person: Person.first)
      chores.receive_stream('chores', { dirty: true })

      expect(chore_names(chores)).to eq(%w[Dishes Garden])
    end
  end

  it 'reloads a relation the lambda returns already loaded' do
    component_class = Class.new(LiveCable::Component) do
      reactive_query :chores, -> { @chores ||= Chore.where(list: 'work').load }
    end
    component = component_class.new('memoized')
    component.chores

    Chore.create!(name: 'Invoices', list: 'work')

    expect(component.chores.map(&:name)).to eq(%w[Report Invoices])
  end

  it 'raises for a table without updated_at' do
    component_class = Class.new(LiveCable::Component) do
      reactive_query :people, -> { Person.all }
    end

    expect { component_class.new('people').people }.to raise_error(LiveCable::Error, /people.*updated_at/)
  end

  it 'has no shared option' do
    expect do
      Class.new(LiveCable::Component) { reactive_query :chores, -> { Chore.all }, shared: true }
    end.to raise_error(ArgumentError, /shared/)
  end
end
