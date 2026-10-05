# frozen_string_literal: true

require 'spec_helper'
require 'active_support/all'

RSpec.describe LiveCable::Delegation do
  # Mutators the bang and alias checks can't find
  non_bang_mutators = {
    Array => %i[[]= << clear concat delete delete_at delete_if fill insert keep_if pop push replace shift unshift],
    Hash => %i[
      []= clear compare_by_identity default= default_proc= delete delete_if keep_if rehash replace shift update
      reverse_update
    ],
  }

  {
    Array => LiveCable::Delegation::Array,
    Hash => LiveCable::Delegation::Hash,
  }.each do |klass, delegation|
    describe delegation do
      let(:decorated) { delegation.instance_methods(false) }

      it "decorates the known non-bang mutators of #{klass}" do
        expect(non_bang_mutators[klass] - decorated).to be_empty
      end

      it "decorates every public bang method of #{klass}" do
        bang_methods = klass.public_instance_methods.grep(/!\z/) - %i[! try!]

        expect(bang_methods - decorated).to be_empty
      end

      it "decorates every alias of a decorated #{klass} mutator" do
        aliases = klass.public_instance_methods.select do |method|
          delegation::MUTATIVE_METHODS.any? do |mutator|
            klass.instance_method(method) == klass.instance_method(mutator)
          end
        end

        expect(aliases - decorated).to be_empty
      end
    end
  end
end
