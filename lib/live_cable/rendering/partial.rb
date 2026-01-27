# frozen_string_literal: true

module LiveCable
  module Rendering
    class Partial
      def initialize(parts)
        @parts = parts
      end

      def for_component(component, view_context)
        klass = Class.new do
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

        @parts.each_with_index do |part, index|
          type, code = part

          next if type == :static

          parsed = Prism.parse(code || '').value
          locals = parsed.locals || []
          local_check_code = +''

          locals.each do |local|
            local_check_code << "store_local(:#{local}, #{local}) if defined?(#{local})\n"
          end

          visitor = DependencyVisitor.new
          visitor.visit(parsed)

          method = <<~METHOD
            def render_part_#{index}(changes)
              if #{'false && ' if type == :code}changes && !(changes | [:component]).intersect?(#{visitor.dependencies.inspect})
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

          klass.class_eval(method, __FILE__, __LINE__ + 1)
        end

        klass.new(component, @parts, view_context)
      end
    end
  end
end
