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
        view, render_context = view_context.with_render_context(self) do
          view_context.render(template: to_partial_path, layout: false, locals:)
        end

        # If we are rendering the initial page, we only need to add the attributes to most parent element
        # as it will re-render again anyway when the socket is available. On this render when the live connection
        # is available, the components can be stored properly, so when each of their sockets connects, it won't need
        # to render them again. This prevents multiple re-renders of children when the parent renders, then renders
        # again, and then the child socket connects and renders that again as well.
        if render_context.root? || live_connection
          view = insert_root_attributes(view, view_context)
        end

        if @previous_render_context
          destroyed = @previous_render_context.children - render_context.children

          destroyed.each(&:destroy)
        end

        if live_connection
          @previous_render_context = render_context
        end

        view
      end

      # @return [Array<LiveCable::Component>]
      def rendered_children
        @previous_render_context&.children || []
      end

      private

      def insert_root_attributes(html, view_context)
        matches = html.match(/(?:\n\s*|^\s*|<!--.*?-->)<([a-zA-Z0-9-]+)/)

        attributes = {
          'live-id' => id,
          'live-component' => self.class.component_string,
          'live-actions' => self.class.allowed_actions.to_json,
        }

        attributes['live-defaults'] = defaults.to_json unless live_connection

        html.insert(matches.end(1), " #{view_context.tag.attributes(attributes)}".html_safe)
        html
      end

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
