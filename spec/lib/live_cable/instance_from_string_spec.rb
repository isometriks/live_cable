# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'LiveCable.instance_from_string' do
  before do
    stub_const('Live::ValidComponent', Class.new(LiveCable::Component) do
      def self.name = 'Live::ValidComponent'
    end)

    stub_const('Live::Nested', Module.new)
    stub_const('Live::Nested::DeepComponent', Class.new(LiveCable::Component) do
      def self.name = 'Live::Nested::DeepComponent'
    end)

    stub_const('Live::NotAComponent', Class.new do
      def self.name = 'Live::NotAComponent'
    end)
  end

  it 'resolves a valid component class and returns an instance' do
    instance = LiveCable.instance_from_string('valid_component', 'test-id')

    expect(instance).to be_a(Live::ValidComponent)
    expect(instance.id).to eq('test-id')
  end

  it 'resolves nested module components' do
    instance = LiveCable.instance_from_string('nested/deep_component', 'test-id')

    expect(instance).to be_a(Live::Nested::DeepComponent)
  end

  it 'raises an error for a missing component' do
    expect do
      LiveCable.instance_from_string('nonexistent', 'test-id')
    end.to raise_error(LiveCable::Error, /not found/)
  end

  it 'raises an error for a class that is not a LiveCable::Component' do
    expect do
      LiveCable.instance_from_string('not_a_component', 'test-id')
    end.to raise_error(LiveCable::Error, /must extend LiveCable::Component/)
  end

  it 'raises an error for an invalid component name' do
    expect do
      LiveCable.instance_from_string('invalid/!@#$%', 'test-id')
    end.to raise_error(LiveCable::Error)
  end
end
