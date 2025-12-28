# frozen_string_literal: true

module LiveCable
  class Component
    module Rendering
      extend ActiveSupport::Concern

      included do
        class_attribute :is_compound, default: false
      end

      class_methods do
        def compound
          self.is_compound = true
        end
      end

      def render
        @rendered = true
        ApplicationController.renderer.render(self, layout: false)
      end

      def to_partial_path
        base = self.class.name.underscore

        if self.class.is_compound
          "#{base}/#{template_state}"
        else
          base
        end
      end

      def template_state
        'component'
      end

      def render_in(view_context)
        # @TODO: Figure out where to put this
        ActionView::Base.annotate_rendered_view_with_filenames = true

        view, render_context = view_context.with_render_context(self) do
          view_context.render(template: to_partial_path, layout: false, locals:)
        end

        if @previous_render_context
          destroyed = @previous_render_context.children - render_context.children

          destroyed.each(&:destroy)
        end

        @previous_render_context = render_context

        view
      end

      private

      def locals
        identifiers = channel ? channel.connection.identifiers.to_a : []

        (all_reactive_variables | (self.class.shared_variables || []) | identifiers).
          to_h { |v| [v, public_send(v)] }.
          merge(
            component: self
          )
      end
    end
  end
end
