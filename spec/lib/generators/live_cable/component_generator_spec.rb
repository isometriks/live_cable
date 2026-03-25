# frozen_string_literal: true

require 'rails_helper'
require 'rails/generators/testing/behavior'
require 'generators/live_cable/component/component_generator'

RSpec.describe LiveCable::Generators::ComponentGenerator do
  include FileUtils

  let(:destination) { Dir.mktmpdir }

  before do
    described_class.start(args, destination_root: destination)
  end

  after do
    rm_rf(destination)
  end

  def read_file(path)
    File.read(File.join(destination, path))
  end

  def file_exists?(path)
    File.exist?(File.join(destination, path))
  end

  describe 'simple component' do
    let(:args) { ['counter'] }

    it 'creates the component file' do
      content = read_file('app/live/counter.rb')
      expect(content).to include('module Live')
      expect(content).to include('class Counter < LiveCable::Component')
    end

    it 'creates the view file' do
      expect(file_exists?('app/views/live/counter.html.live.erb')).to be true
    end
  end

  describe 'component with reactive variables and actions' do
    let(:args) { %w[counter --reactive count:integer name:string --actions increment decrement] }

    it 'includes reactive declarations' do
      content = read_file('app/live/counter.rb')
      expect(content).to include('reactive :count, -> { 0 }')
      expect(content).to include('reactive :name, -> { "" }')
    end

    it 'includes action declarations and method stubs' do
      content = read_file('app/live/counter.rb')
      expect(content).to include('actions :increment, :decrement')
      expect(content).to include('def increment')
      expect(content).to include('def decrement')
    end
  end

  describe 'compound component' do
    let(:args) { %w[wizard --compound] }

    it 'includes the compound declaration' do
      content = read_file('app/live/wizard.rb')
      expect(content).to include('compound')
    end

    it 'creates the view in a subdirectory' do
      expect(file_exists?('app/views/live/wizard/component.html.live.erb')).to be true
    end
  end

  describe 'namespaced component' do
    let(:args) { %w[chat/message --reactive body:string] }

    it 'creates the component with nested modules' do
      content = read_file('app/live/chat/message.rb')
      expect(content).to include('module Live')
      expect(content).to include('module Chat')
      expect(content).to include('class Message < LiveCable::Component')
      expect(content).to include('reactive :body, -> { "" }')
    end

    it 'creates the view in the namespaced directory' do
      expect(file_exists?('app/views/live/chat/message.html.live.erb')).to be true
    end
  end

  describe 'reactive variable type defaults' do
    let(:args) do
      %w[example --reactive count:integer name:string active:boolean items:array data:hash other]
    end

    it 'uses correct defaults for each type' do
      content = read_file('app/live/example.rb')
      expect(content).to include('reactive :count, -> { 0 }')
      expect(content).to include('reactive :name, -> { "" }')
      expect(content).to include('reactive :active, -> { false }')
      expect(content).to include('reactive :items, -> { [] }')
      expect(content).to include('reactive :data, -> { {} }')
      expect(content).to include('reactive :other, -> { nil }')
    end
  end
end
