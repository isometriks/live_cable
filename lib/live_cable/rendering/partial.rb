# frozen_string_literal: true

require_relative 'partial_renderer'

module LiveCable
  module Rendering
    class Partial
      CACHE = Concurrent::Map.new

      # @return [Partial]
      def self.fetch(key, digest)
        cached_digest, partial = CACHE[key]
        return partial if cached_digest == digest

        partial = yield
        CACHE[key] = [digest, partial]
        partial
      end

      # @return [Hash{Integer=>Array<String>}] The statics of the template's tree parts
      attr_reader :statics

      # @return [Hash{Symbol=>Streams::Stream}] The collection streams the template renders
      attr_reader :streams

      def initialize(parts, metadata, identifier, virtual_path = nil, template = nil, statics = {}, streams = {})
        @parts = parts
        @metadata = metadata
        @identifier = identifier
        @virtual_path = virtual_path
        @template = template
        @statics = statics.transform_values { |strings| strings.map(&:freeze).freeze }.freeze
        @streams = streams.to_h do |name, stream|
          [name, Streams::Stream.new(name:, virtual_path: stream[:virtual_path] || virtual_path,
            **stream.slice(:part, :path, :scope, :user_id_code, :key_id))]
        end.freeze
        @renderer_class = build_renderer_class(streams)
      end

      # @return [PartialRenderer]
      def for_component(component, view_context, render_context: nil)
        renderer_class.new(component, parts, view_context, virtual_path, template, render_context:)
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

      # @return [String, nil]
      attr_reader :virtual_path

      # @return [ActionView::Template, nil]
      attr_reader :template

      # @return [Class<PartialRenderer>]
      attr_reader :renderer_class

      def build_renderer_class(streams)
        metadata = @metadata
        stream_metadata = @streams
        stream_rows = @streams.values.map { |stream| [stream, streams[stream.name]] }

        Class.new(PartialRenderer) do
          # Store metadata as class variable for access in render methods
          @metadata = metadata
          @streams = stream_metadata
          @row_method_calls = stream_rows.flat_map { |_, compiled| compiled[:component_method_calls] }.uniq

          class << self
            attr_reader :metadata, :streams, :row_method_calls
          end

          metadata.each_with_index do |part_metadata, index|
            next unless part_metadata

            type = part_metadata[:type]
            code = part_metadata[:code]
            component_dependencies = part_metadata[:component_dependencies]
            component_method_calls = part_metadata[:component_method_calls] || []
            local_dependencies = part_metadata[:local_dependencies]
            exposed_local_reads = part_metadata[:exposed_local_reads]
            defines_locals = part_metadata[:defines_locals]
            local_check_code = part_metadata[:local_check_code]

            # A part whose top-level local a later part reads always runs
            skip_check = if type == :code || part_metadata[:feeds_later_parts] || part_metadata[:uses_view_flow]
                           ''
                         else
                           <<~SKIP_CHECK
                             return nil if should_skip_part?(
                               __live_changes,
                               #{component_dependencies.inspect},
                               #{component_method_calls.inspect},
                               #{exposed_local_reads.inspect}
                             )
                           SKIP_CHECK
                         end

            # Earlier parts' locals become Ruby locals in this part's method, as
            # they would be in one ERB method body.
            local_init_code = local_dependencies.map { |dep| "#{dep} = @locals[:#{dep}]" }.join("\n")

            # A tree part's code returns its node rather than writing to the
            # buffer (see TreeBuilder).
            capture = type == :tree ? 'render_tree' : 'with_buffer'

            # Part code runs inside this method, so its parameter must not shadow a name the template uses.
            class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
              def render_part_#{index}(__live_changes)
                #{skip_check}
                # Mark locals defined by this part as dirty
                mark_locals_dirty(#{defines_locals.inspect})

                #{capture} do
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

          # A row renders on its own, from its item and its key
          stream_rows.each do |stream, compiled|
            class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
              def #{stream.row_method}(#{compiled[:param]}, #{Streams::KEY})
                #{compiled[:code]}
              end
            RUBY
            next unless stream.user_id_code

            class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
              def #{stream.id_method}(#{compiled[:param]})
                #{stream.user_id_code}
              end
            RUBY
          end
        end
      end
    end
  end
end
