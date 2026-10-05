# frozen_string_literal: true

module LiveCable
  module Delegation
    module Array
      extend Methods

      GETTER_METHODS = %i[
        []
        at
        chunk
        collect
        compact
        cycle
        detect
        dig
        drop
        drop_while
        fetch
        filter
        find
        find_all
        first
        flatten
        grep
        grep_v
        group_by
        last
        map
        max
        max_by
        min
        min_by
        reject
        reverse
        rotate
        sample
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

      ITERATOR_METHODS = %i[
        each_cons
        each_slice
        each_with_index
        each_with_object
        reverse_each
      ].freeze

      MUTATIVE_METHODS = %i[
        []=
        <<
        append
        clear
        collect!
        compact!
        compact_blank!
        concat
        delete
        delete_at
        delete_if
        extract!
        extract_options!
        fill
        filter!
        flatten!
        insert
        keep_if
        map!
        pop
        prepend
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
      decorate_iterators ITERATOR_METHODS
      decorate_mutators MUTATIVE_METHODS

      def each(&)
        return to_enum(:each) { size } unless block_given?

        __getobj__.each do |v|
          yield create_delegator(v)
        end
      end
    end
  end
end
