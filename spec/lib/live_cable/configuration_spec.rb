# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LiveCable::Configuration do
  describe '#verbose_errors' do
    it 'defaults to true in non-production' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('test'))

      config = described_class.new

      expect(config.verbose_errors).to be true
    end

    it 'defaults to false in production' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))

      config = described_class.new

      expect(config.verbose_errors).to be false
    end
  end

  describe 'LiveCable.configure' do
    it 'yields the configuration' do
      LiveCable.configure do |config|
        expect(config).to be_a(described_class)
      end
    end

    it 'allows setting verbose_errors' do
      original = LiveCable.configuration.verbose_errors

      LiveCable.configure { |config| config.verbose_errors = !original }

      expect(LiveCable.configuration.verbose_errors).to eq(!original)
    ensure
      LiveCable.configure { |config| config.verbose_errors = original }
    end
  end
end
