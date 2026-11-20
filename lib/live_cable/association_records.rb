# frozen_string_literal: true

module LiveCable
  # An association checks what it's given with is_a?(klass), which a reactive
  # record's wrapper isn't, so assigning one raised AssociationTypeMismatch.
  module AssociationRecords
    module SingularAssociation
      def writer(record)
        super(Delegator.unwrap(record))
      end
    end

    module CollectionAssociation
      def writer(records)
        super(Delegator.unwrap(records))
      end

      def concat(*records)
        super(*Delegator.unwrap(records))
      end
    end
  end
end
