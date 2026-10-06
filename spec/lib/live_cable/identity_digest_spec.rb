# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LiveCable::IdentityDigest do
  it 'digests the same values to the same string' do
    expect(described_class.digest('bob', 7)).to eq(described_class.digest('bob', 7))
  end

  it 'digests different values to different strings' do
    expect(described_class.digest('bob')).not_to eq(described_class.digest('alice'))
    expect(described_class.digest('bob', nil)).not_to eq(described_class.digest('bob', 'admin'))
  end

  it 'does not reveal the values' do
    expect(described_class.digest('bob@example.com')).not_to include('bob')
  end

  it 'is keyed by the application secret, so a plain hash of a guessed id does not match it' do
    expect(described_class.digest('7')).not_to eq(Digest::SHA256.hexdigest('["7"]'))
  end

  it 'identifies records by their GlobalID, as ActionCable identifies a connection' do
    record = Struct.new(:to_gid_param).new('Z2lkOi8vZHVtbXkvVXNlci83')

    expect(described_class.digest(record)).to eq(described_class.digest('Z2lkOi8vZHVtbXkvVXNlci83'))
  end

  describe 'live_cable_identity_tag' do
    it 'renders a meta tag carrying the digest' do
      html = ApplicationController.helpers.live_cable_identity_tag('bob')

      expect(html).to eq(%(<meta name="live-cable-identity" content="#{described_class.digest('bob')}">))
    end
  end
end
