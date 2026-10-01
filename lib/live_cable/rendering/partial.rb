# frozen_string_literal: true

require_relative 'partial_renderer'

module LiveCable
  module Rendering
    class Partial
      def initialize(parts, metadata, identifier)
        @parts = parts
        @metadata = metadata
        @identifier = identifier
        @renderer_class = build_renderer_class
      end

      # @return [PartialRenderer]
      def for_component(component, view_context)
        renderer_class.new(component, parts, view_context)
      end

      # ActionView calls this when a template is rendered as a partial or a plain
      # template; only Component#render_in can render a Partial.
      def to_s
        raise LiveCable::Error,
          "#{identifier} is a component template and can only be rendered by its component. " \
          'Render the component with live(...) or render(component), or make the partial a .html.erb template.'
      end

      private

      # @return [Array]
      attr_reader :parts

      # @return [Array]
      attr_reader :metadata

      # @return [String]
      attr_reader :identifier

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

            # A part whose top-level local a later part reads always runs
            skip_check = if type == :code || part_metadata[:feeds_later_parts]
                           ''
                         else
                           <<~SKIP_CHECK
                             return nil if should_skip_part?(
                               __live_changes,
                               #{component_dependencies.inspect},
                               #{component_method_calls.inspect},
                               #{local_dependencies.inspect}
                             )
                           SKIP_CHECK
                         end

            # Initialize local variables from previous parts so that operator
            # assignments (||=, &&=, +=) work correctly. Without this, Ruby
            # treats them as fresh nil locals instead of resolving via method_missing.
            local_init_code = local_dependencies.map { |dep| "#{dep} = @locals[:#{dep}]" }.join("\n")

            # Part code runs inside this method, so its parameter must not shadow a name the template uses.
            class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
              def render_part_#{index}(__live_changes)
                #{skip_check}
                # Mark locals defined by this part as dirty
                mark_locals_dirty(#{defines_locals.inspect})

                with_buffer do
                  begin
                    #{local_init_code}
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
