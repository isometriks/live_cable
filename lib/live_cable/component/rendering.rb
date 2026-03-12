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
          result = view_context.render(template: to_partial_path, locals:)

          unless result.is_a?(LiveCable::Rendering::Partial)
            warn(
              "[LiveCable Warning] #{to_partial_path} was rendered without using a .live.erb template, " \
              'this will be less performant.'
            )

            next result
          end

          # Track which template we're rendering
          current_template_path = to_partial_path

          # Initialize static_sent hash and track previous template
          @static_sent ||= {}
          @previous_template_path ||= nil

          # Detect template change - if template changed, force dynamic render
          template_changed = previous_template_path && previous_template_path != current_template_path

          # Determine if we should send diffs or full render
          changes = if static_sent[current_template_path]
                      # Static already sent for this template
                      template_changed ? :dynamic : live_connection&.changeset_for(self)
                    else
                      :all
                    end

          @previous_template_path = current_template_path

          result.for_component(self, view_context).render(changes)
        end

        unless (partial = view.is_a?(Array))
          view = [view]
        end

        # If we are rendering the initial page, we only need to add the attributes to most parent element
        # as it will re-render again anyway when the socket is available. On this render when the live connection
        # is available, the components can be stored properly, so when each of their sockets connects, it won't need
        # to render them again. This prevents multiple re-renders of children when the parent renders, then renders
        # again, and then the child socket connects and renders that again as well.
        if (render_context.root? || live_connection) && !view[0].nil?
          view[0] = insert_root_attributes(view[0], view_context)
        end

        if previous_render_context
          destroyed = previous_render_context.children - render_context.children
          destroyed.each(&:destroy)
        end

        # We didn't get a LiveCable Partial, so just return it with one part
        unless partial
          if live_connection && render_context.root?
            return LiveCable::Rendering::RenderResult.new(live_id, view, to_partial_path)
          else
            return view[0]
          end
        end

        if live_connection
          @static_sent[previous_template_path] = true

          @previous_render_context = render_context
          result = LiveCable::Rendering::RenderResult.new(live_id, view, to_partial_path)

          if render_context.root?
            result.child_results = render_context.render_results

            return result
          else
            # Always use LiveCable placeholder for non-root children
            # This allows JavaScript to store the component before subscription connects
            render_context << result

            return "<LiveCable child-live-id=\"#{live_id}\"></LiveCable>".html_safe
          end
        end

        view_context.safe_join(view)
      end

      # @return [Array<LiveCable::Component>]
      def rendered_children
        previous_render_context&.children || []
      end

      private

      # @return [Hash<String, Boolean>]
      attr_reader :static_sent

      # @return [String, nil]
      attr_reader :previous_template_path

      # @return [LiveCable::RenderContext, nil]
      attr_reader :previous_render_context

      def insert_root_attributes(html, view_context)
        matches = html.match(/(?:\n\s*|^\s*|<!--.*?-->)<([a-zA-Z0-9-]+)/)

        attributes = {
          'live-id' => id,
          'live-component' => self.class.component_string,
          'live-actions' => self.class.allowed_actions.to_json,
          'data-live-status-value' => subscribed? ? 'subscribed' : 'disconnected',
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
