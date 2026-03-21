# frozen_string_literal: true

module LiveCable
  class Component
    module MethodDependencyTracking
      extend ActiveSupport::Concern

      class_methods do
        # Get the analyzer instance for this component class.
        # Lazily creates and caches the analyzer on first access.
        # @return [LiveCable::Rendering::MethodAnalyzer]
        def method_dependencies_analyzer
          @method_dependencies_analyzer ||= begin
            analyzer = LiveCable::Rendering::MethodAnalyzer.new(self)
            analyzer.analyze_all_methods
            analyzer
          end
        end
      end
    end
  end
end
