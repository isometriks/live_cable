# frozen_string_literal: true

require_relative 'partial_renderer'

module LiveCable
  module Rendering
    class Partial
      def initialize(parts, metadata)
        @parts = parts
        @metadata = metadata
        @renderer_class = build_renderer_class
      end

      def for_component(component, view_context)
        @renderer_class.new(component, @parts, view_context)
      end

      private

      def build_renderer_class
        metadata = @metadata

        Class.new(PartialRenderer) do
          # Store metadata as class variable for access in render methods
          @metadata = metadata

          class << self
            attr_reader :metadata
          end

          metadata.each_with_index do |part_metadata, index|
            next unless part_metadata

            type = part_metadata[:type]
            code = part_metadata[:code]
            component_dependencies = part_metadata[:component_dependencies]
            local_dependencies = part_metadata[:local_dependencies]
            defines_locals = part_metadata[:defines_locals]
            local_check_code = part_metadata[:local_check_code]

            method_def = <<~METHOD
              def render_part_#{index}(changes)
                metadata = self.class.metadata[#{index}]
                
                # Skip if no dependencies changed and no local dependencies are dirty
                if #{'false && ' if type == :code}changes && 
                   !(changes | [:component]).intersect?(#{component_dependencies.inspect}) &&
                   !@dirty_locals.intersect?(#{local_dependencies.inspect})
                  return nil
                end

                # Mark locals defined by this part as dirty
                mark_locals_dirty(#{defines_locals.inspect})

                with_buffer do
                  begin
                    #{code}
                  ensure
                    #{local_check_code}
                  end
                end
              end
            METHOD

            class_eval(method_def, __FILE__, __LINE__ + 1)
          end
        end
      end
    end
  end
end
