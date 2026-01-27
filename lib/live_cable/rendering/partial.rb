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
          metadata.each_with_index do |part_metadata, index|
            next unless part_metadata

            type = part_metadata[:type]
            code = part_metadata[:code]
            dependencies = part_metadata[:dependencies]
            local_check_code = part_metadata[:local_check_code]

            method_def = <<~METHOD
              def render_part_#{index}(changes)
                if #{'false && ' if type == :code}changes && !(changes | [:component]).intersect?(#{dependencies.inspect})
                  return
                end

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
