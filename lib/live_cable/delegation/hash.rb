# frozen_string_literal: true

module LiveCable
  module Delegation
    module Hash
      extend Methods

      MUTATIVE_METHODS = %i[
        []=
        clear
        compact!
        deep_merge!
        deep_stringify_keys!
        deep_transform_keys!
        deep_transform_values!
        delete
        delete_if
        except!
        extract!
        keep_if
        merge!
        rehash
        reject!
        reverse_merge!
        select!
        shift
        stringify_keys!
        symbolize_keys!
        transform_keys!
        transform_values!
        update
      ].freeze

      decorate_getter :[]
      decorate_mutators MUTATIVE_METHODS
    end
  end
end
