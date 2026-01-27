# frozen_string_literal: true

module LiveCable
  module Rendering
    # Base class for partial renderers with common functionality
    class PartialRenderer
      attr_reader :component

      def initialize(component, parts, view_context)
        @component = component
        @parts = parts
        @view_context = view_context
      end

      def render(changes = nil)
        @locals = {}
        @parts.each_with_index.map do |_, index|
          send("render_part_#{index}", changes)
        end
      end

      def method_missing(method, ...)
        if @locals.key?(method)
          return @locals[method]
        end

        if @view_context.respond_to?(method)
          return @view_context.public_send(method, ...)
        end

        if @component.respond_to?(method)
          return @component.public_send(method, ...)
        end

        super
      end

      def respond_to_missing?(method, _include_private = false)
        @locals.key?(method) || @view_context.respond_to?(method) || @component.respond_to?(method)
      end

      private

      def with_buffer(&block)
        @output_buffer = ActionView::OutputBuffer.new
        block.call
        @output_buffer.to_s
      end

      def store_local(name, value)
        @locals[name] = value
      end
    end
  end
end
