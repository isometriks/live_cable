# frozen_string_literal: true

module Live
  class PersonChores < LiveCable::Component
    reactive :person, -> { Person.first }

    reactive_query :chores, -> { person.chores }

    after_connect do
      stream_from('chores', coder: ActiveSupport::JSON) { |data| data['dirty'] ? dirty(:chores) : refresh }
    end
  end
end
