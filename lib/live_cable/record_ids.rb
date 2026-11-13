# frozen_string_literal: true

module LiveCable
  # ActiveRecord tells a list of ids from one id with is_a?(Array), which a
  # reactive Array isn't, so it found, destroyed or updated a single record.
  module RecordIds
    module FinderMethods
      private

      def find_with_ids(*ids)
        super(*Delegator.unwrap(ids))
      end
    end

    module Relation
      def destroy(id)
        super(Delegator.unwrap(id))
      end
    end

    module CoreClassMethods
      def find(*ids, &)
        super(*Delegator.unwrap(ids), &)
      end
    end

    module PersistenceClassMethods
      def destroy(id)
        super(Delegator.unwrap(id))
      end

      def update(id_or_attributes, *)
        super(Delegator.unwrap(id_or_attributes), *)
      end

      def update!(id_or_attributes, *)
        super(Delegator.unwrap(id_or_attributes), *)
      end
    end
  end
end
