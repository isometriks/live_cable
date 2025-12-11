# frozen_string_literal: true

module LiveCable
  module Delegation
    module Array
      extend Methods
      extend Enumerable

      GETTER_METHODS = %i[
        []
        chunk
        collect
        compact
        cycle
        drop
        drop_while
        filter
        find_all
        first
        flatten
        grep
        grep_v
        group_by
        last
        map
        reject
        reverse
        rotate
        select
        shuffle
        slice
        sort
        sort_by
        take
        take_while
        transpose
        uniq
        zip
      ].freeze

      MUTATIVE_METHODS = %i[
        []=
        <<
        clear
        compact!
        concat
        delete
        delete_at
        delete_if
        fill
        flatten!
        insert
        keep_if
        map!
        pop
        push
        reject!
        replace
        reverse!
        rotate!
        select!
        shift
        shuffle!
        slice!
        sort!
        sort_by!
        uniq!
        unshift
      ].freeze

      decorate_getters GETTER_METHODS
      decorate_mutators MUTATIVE_METHODS

      def each(&)
        __getobj__.each do |v|
          yield create_delegator(v)
        end
      end
    end
  end
end
