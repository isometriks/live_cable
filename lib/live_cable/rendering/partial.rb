# frozen_string_literal: true

require_relative 'partial_renderer'

module LiveCable
  module Rendering
    class Partial
      def initialize(output_buffer, parts, metadata)
        @output_buffer = output_buffer
        @parts = parts
        @metadata = metadata
        @renderer_class = build_renderer_class
      end

      # @return [PartialRenderer]
      def for_component(component, view_context)
        renderer_class.new(@output_buffer, component, parts, view_context)
      end

      private

      # @return [Array]
      attr_reader :parts

      # @return [Array]
      attr_reader :metadata

      # @return [Class<PartialRenderer>]
      attr_reader :renderer_class

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
            component_method_calls = part_metadata[:component_method_calls] || []
            local_dependencies = part_metadata[:local_dependencies]
            defines_locals = part_metadata[:defines_locals]
            local_check_code = part_metadata[:local_check_code]

            # Code blocks always execute (they define locals that other parts need)
            # Expression blocks can be skipped if dependencies haven't changed
            skip_check = if type == :code
                           ''
                         else
                           <<~SKIP_CHECK
                             return nil if should_skip_part?(
                               changes,
                               #{component_dependencies.inspect},
                               #{component_method_calls.inspect},
                               #{local_dependencies.inspect}
                             )
                           SKIP_CHECK
                         end

            class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
              def render_part_#{index}(changes)
                #{skip_check}
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
            RUBY
          end
        end
      end
    end
  end
end
