# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../fixtures/test_analyzable_component'

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
end
