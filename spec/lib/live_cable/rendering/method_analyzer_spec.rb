# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../fixtures/test_analyzable_component'
require_relative '../../../fixtures/test_same_file_methods_component'

RSpec.describe LiveCable::Rendering::MethodAnalyzer do
  let(:component_class) { TestAnalyzableComponent }
  let(:analyzer) { described_class.new(component_class) }

  describe '#analyze_all_methods' do
    it 'analyzes all public methods' do
      dependencies = analyzer.analyze_all_methods

      expect(dependencies).to be_a(Hash)
      expect(dependencies.keys).to include(:display_name, :greeting, :full_greeting, :summary, :static_message)
    end

    it 'tracks direct reactive variable dependencies' do
      dependencies = analyzer.analyze_all_methods

      expect(dependencies[:greeting][:reactive_vars]).to include(:username)
      expect(dependencies[:display_name][:reactive_vars]).to include(:username)
      expect(dependencies[:summary][:reactive_vars]).to include(:count)
      # summary does NOT directly depend on username - only transitively through display_name
      expect(dependencies[:summary][:reactive_vars]).not_to include(:username)
    end

    it 'tracks method call dependencies' do
      dependencies = analyzer.analyze_all_methods

      expect(dependencies[:full_greeting][:methods]).to include(:greeting)
      expect(dependencies[:summary][:methods]).to include(:display_name, :count)
    end

    it 'handles methods with no dependencies' do
      dependencies = analyzer.analyze_all_methods

      expect(dependencies[:static_message][:reactive_vars]).to be_empty
    end

    it 'returns empty dependencies for a class with no Ruby source location' do
      # Anonymous class: name is nil, const_source_location cannot be resolved
      anonymous = Class.new(LiveCable::Component)

      expect do
        expect(described_class.new(anonymous).analyze_all_methods).to eq({})
      end.not_to raise_error
    end

    it 'returns empty dependencies when const_source_location is nil' do
      named = Class.new(LiveCable::Component) do
        def self.name = 'Live::PhantomComponent'
      end
      allow(Object).to receive(:const_source_location).and_return(nil)

      expect(described_class.new(named).analyze_all_methods).to eq({})
    end

    it 'remembers that a class could not be analyzed rather than looking again on every render' do
      named = Class.new(LiveCable::Component) do
        def self.name = 'Live::PhantomComponent'
      end
      allow(Object).to receive(:const_source_location).and_return(nil)
      analyzer = described_class.new(named)

      analyzer.expanded_dependencies(:foo)
      analyzer.expanded_dependencies(:bar)

      expect(Object).to have_received(:const_source_location).once
    end
  end

  describe '#analyze_method' do
    it 'returns dependencies for a specific method' do
      result = analyzer.analyze_method(:greeting)

      expect(result).to be_a(Hash)
      expect(result[:reactive_vars]).to include(:username)
    end

    it 'returns nil for non-existent methods' do
      result = analyzer.analyze_method(:nonexistent)

      expect(result).to be_nil
    end
  end

  describe '#expanded_dependencies' do
    it 'expands transitive method call dependencies' do
      result = analyzer.expanded_dependencies(:full_greeting)

      # full_greeting calls greeting, which depends on username
      expect(result).to include(:username)
    end

    it 'expands nested method dependencies' do
      result = analyzer.expanded_dependencies(:summary)

      # summary directly calls count and transitively calls username through display_name
      expect(result).to include(:count, :username)
    end

    it 'checks control structures' do
      result = analyzer.expanded_dependencies(:case_when_username)
      expect(result).to include(:username)
    end

    it 'returns empty set for methods with no dependencies' do
      result = analyzer.expanded_dependencies(:static_message)

      expect(result).to be_empty
    end

    it 'correctly identifies reactive variable dependency in filtered_todos' do
      result = analyzer.expanded_dependencies(:filtered_todos)

      # filtered_todos calls todos, which is a reactive variable
      expect(result).to include(:todos)
    end
  end

  context 'when other defs in the same file share a method name' do
    let(:component_class) { TestSameFileMethodsComponent }

    it 'keeps dependencies when a later def self.x shares the name' do
      expect(analyzer.expanded_dependencies(:title)).to include(:count)
    end

    it 'keeps dependencies when a later class << self method shares the name' do
      expect(analyzer.expanded_dependencies(:label)).to include(:count)
    end

    it 'keeps dependencies when a Struct block method shares the name' do
      expect(analyzer.expanded_dependencies(:summary)).to include(:count)
    end

    it 'keeps dependencies when a nested class method shares the name' do
      expect(analyzer.expanded_dependencies(:heading)).to include(:count)
    end

    it 'keeps dependencies when another class in the file shares the name' do
      expect(analyzer.expanded_dependencies(:caption)).to include(:count)
    end

    it 'ignores singleton methods' do
      expect(analyzer.analyze_method(:registry_name)).to be_nil
    end

    it 'follows methods from a module defined in the same file' do
      expect(analyzer.expanded_dependencies(:helper_title)).to include(:count)
    end
  end
end
