# frozen_string_literal: true

module LiveCable
  module Delegation
    module Hash
      extend Methods

      GETTER_METHODS = %i[
        []
        dig
        fetch
      ].freeze

      COLLECTION_GETTER_METHODS = %i[
        fetch_values
        values
        values_at
      ].freeze

      ITERATOR_METHODS = %i[
        detect
        each_with_index
        each_with_object
        find
      ].freeze

      MUTATIVE_METHODS = %i[
        []=
        clear
        compact!
        compact_blank!
        compare_by_identity
        deep_merge!
        deep_stringify_keys!
        deep_symbolize_keys!
        deep_transform_keys!
        deep_transform_values!
        default=
        default_proc=
        delete
        delete_if
        except!
        extract!
        filter!
        keep_if
        merge!
        rehash
        reject!
        replace
        reverse_merge!
        reverse_update
        select!
        shift
        slice!
        store
        stringify_keys!
        symbolize_keys!
        to_options!
        transform_keys!
        transform_values!
        update
        with_defaults!
      ].freeze

      decorate_getters GETTER_METHODS
      decorate_collection_getters COLLECTION_GETTER_METHODS
      decorate_iterators ITERATOR_METHODS
      decorate_mutators MUTATIVE_METHODS

      # Like Hash#each, yields the key and value separately only to blocks that
      # take more than one argument and a [key, value] pair to the rest.
      def each_pair(&block)
        return to_enum(:each_pair) { size } unless block

        split = block.arity > 1

        __getobj__.each_pair do |key, value|
          value = create_delegator(value)

          split ? yield(key, value) : yield([key, value])
        end
      end
      alias each each_pair

      def each_value
        return to_enum(:each_value) { size } unless block_given?

        __getobj__.each_value { |value| yield create_delegator(value) }
      end
    end
  end
end
