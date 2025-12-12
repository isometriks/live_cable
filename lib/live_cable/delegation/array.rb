# frozen_string_literal: true

module LiveCable
  module Delegation
    module Array
      extend Methods

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

      decorate_getter :[]
      decorate_mutators MUTATIVE_METHODS
    end
  end
end
