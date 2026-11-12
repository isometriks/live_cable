# frozen_string_literal: true

module Live
  class ChoreTotals < LiveCable::Component
    reactive_query :open_count, -> { Chore.where(done: false) }, &:count

    reactive_query :assigned, -> { Chore.eager_load(:person).where.not(people: { id: nil }).order(:id) } do |relation|
      relation.map { |chore| "#{chore.name}: #{chore.person.name}" }
    end

    reactive_query :names, -> { Chore.select(:id, :name).order(:id) } do |relation|
      relation.map(&:name)
    end

    after_connect { stream_from('chores') { refresh } }
  end
end
