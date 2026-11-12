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
        return render_in(live_connection.view_context) if live_connection

        ApplicationController.renderer.render(self, layout: false)
      end

      def to_partial_path
        base = self.class.name.underscore

        if self.class.is_compound
          state = variant
          raise LiveCable::Error, "#{self.class.name}#variant must return a non-nil value" if state.nil?

          "#{base}/#{state}"
        else
          base
        end
      end

      def variant
        'component'
      end

      def render_in(view_context)
        template_changed = false

        view, render_context = view_context.with_render_context(self) do
          result = view_context.render(template: to_partial_path, locals: locals(view_context))

          unless result.is_a?(LiveCable::Rendering::Partial)
            LiveCable.warn_once(
              "[LiveCable] #{to_partial_path} was rendered without a .live.erb template; " \
              'the full template diff is sent on every change, which is less performant.'
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

          result.for_component(self, view_context).render_changes(changes)
        end

        # A render callback halted this inline render: the client keeps the
        # child's last render, and its children stay owned but unrendered
        if view.nil? && live_connection && !render_context.root?
          render_context.inherit_skipped(previous_render_context) if previous_render_context
          @previous_render_context = render_context

          # Without a Partial the client stores nothing for the child to keep
          return @inline_html || child_placeholder(view_context)
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
          render_context.inherit_skipped(previous_render_context) unless template_changed
          owned = render_context.owned_children.to_set(&:object_id)
          dropped = previous_render_context.owned_children.reject { |child| owned.include?(child.object_id) }
          live_connection.drop(dropped)
        end

        # We didn't get a LiveCable Partial, so just return it with one part
        unless partial
          if live_connection && render_context.root?
            return LiveCable::Rendering::RenderResult.new(live_id, view, to_partial_path)
          else
            @inline_html = view[0] if live_connection

            return view[0]
          end
        end

        if live_connection
          @inline_html = nil

          # A frame with no subscription to carry it is dropped, so the client never gets these parts
          @static_sent[previous_template_path] = true if render_context.root_component.subscribed?

          @previous_render_context = render_context
          result = LiveCable::Rendering::RenderResult.new(live_id, view, to_partial_path)

          if render_context.root?
            result.child_results = render_context.render_results

            return result
          else
            # Always use LiveCable placeholder for non-root children
            # This allows JavaScript to store the component before subscription connects
            render_context << result

            return child_placeholder(view_context)
          end
        end

        view_context.safe_join(view)
      end

      # @return [Array<LiveCable::Component>]
      def rendered_children
        previous_render_context&.children || []
      end

      # @return [Array<LiveCable::Component>]
      def owned_children
        previous_render_context&.owned_children || []
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

        unless matches
          preview = html.to_s.strip[0, 80]
          raise LiveCable::Error,
            "#{self.class.name} template must have a single root HTML element " \
            "(could not find an opening tag in the first part of rendered output: #{preview.inspect})"
        end

        attributes = {
          'live-id' => id,
          'live-component' => self.class.component_string,
          'live-actions' => self.class.allowed_actions.to_json,
          'data-live-status-value' => subscribed? ? 'subscribed' : 'disconnected',
        }

        # Sign the defaults so the client can't tamper with them on the round
        # trip and set non-writable reactive variables at subscribe time.
        unless live_connection
          attributes['live-defaults'] = LiveCable::DefaultsSigner.sign(defaults, live_id)
        end

        # Build a new string rather than mutating `html` in place with
        # String#insert - the rendered part may be frozen, which would raise
        # a FrozenError.
        insert_at = matches.end(1)
        rendered_attributes = " #{view_context.tag.attributes(attributes)}"
        "#{html[0...insert_at]}#{rendered_attributes}#{html[insert_at..]}".html_safe
      end

      def child_placeholder(view_context)
        view_context.content_tag('LiveCable', nil, 'child-live-id' => live_id)
      end

      def locals(view_context)
        identifiers = channel ? channel.connection.identifiers.to_a : []

        (all_reactive_variables | (self.class.shared_variables || []) | identifiers).
          to_h { |v| [v, view_context.live_cable_unwrap(public_send(v))] }.
          merge(
            component: self
          )
      end
    end
  end
end
