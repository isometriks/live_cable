# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LiveCable::Observer do
  let(:container) { LiveCable::Container.new }
  let(:observer) { described_class.new(container) }

  describe '#notify' do
    it 'marks the variable as dirty in the container' do
      observer.notify(:username)

      expect(container.changeset).to include(:username)
    end

    it 'marks multiple variables as dirty' do
      observer.notify(:username)
      observer.notify(:email)

      expect(container.changeset).to contain_exactly(:username, :email)
    end

    it 'does not duplicate variables in the changeset' do
      observer.notify(:username)
      observer.notify(:username)
      observer.notify(:username)

      expect(container.changeset).to eq([:username])
    end
  end
end
