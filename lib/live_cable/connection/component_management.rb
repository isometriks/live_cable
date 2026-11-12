# frozen_string_literal: true

module LiveCable
  class Connection
    module ComponentManagement
      extend ActiveSupport::Concern

      def get_component(id)
        components[id]
      end

      # @param placer [LiveCable::Component, nil] the parent whose render placed it
      def add_component(component, placer: nil)
        synchronize do
          component.live_connection = self
          components[component.live_id] = component
          refused.delete(component.live_id)
          @placed&.store(component, placer)
        end
      end

      # @return [LiveCable::Component, nil] the refused component a parent's
      #   render keeps in place of building it again
      def refused_component(live_id)
        refused[live_id]
      end

      # @param component [LiveCable::Component] from #refused_component
      # @param placer [LiveCable::Component]
      def keep_refused(component, placer:)
        @placed&.store(component, placer)
      end

      # Destroys the children a render no longer places. During a render cycle
      # that waits for its end, as another parent may place them again.
      #
      # @param children [Array<LiveCable::Component>]
      def drop(children)
        @dropped ? @dropped.merge(children) : release(children, destroy: true)
      end

      # Disconnects a component the client let go of, with the children it
      # renders, which the client lets go of with it
      #
      # @param component [LiveCable::Component]
      def disconnect_component(component)
        return unless components[component.live_id].equal?(component)

        children = component.owned_children | placed_by(component)
        leave(component)
        release(children)
      end

      # Takes a refused component off the connection, but keeps it for the
      # parent that owns it, so the parent's renders don't build it again
      #
      # @param component [LiveCable::Component]
      def refuse_component(component)
        return unless components[component.live_id].equal?(component)

        disconnect_component(component)
        refused[component.live_id] = component
      end

      def remove_component(component)
        synchronize do
          next unless components[component.live_id].equal?(component)

          # Clean up the container to break observer reference chains
          container = containers.delete(component.live_id)
          container&.cleanup

          components.delete(component.live_id)

          # Clean up shared container if no components remain
          cleanup_shared_container
        end
      end

      private

      def dropping
        return yield if @dropped

        begin
          @dropped = Set.new.compare_by_identity
          @placed = {}.compare_by_identity
          yield
          release(@dropped, destroy: true)
        ensure
          @dropped = @placed = nil
        end
      end

      # Takes them, with their children, off the connection, so rendering
      # their live ids again builds new components
      def release(children, destroy: false)
        children.each do |child|
          next if placed?(child)
          next forget_refused(child) unless components[child.live_id].equal?(child)

          grandchildren = child.owned_children
          child.broadcast_destroy if destroy
          leave(child)
          release(grandchildren, destroy:)
        rescue StandardError, ScriptError => error
          # Reported, not raised: whatever let the child go did nothing wrong
          Rails.error.report(error)
        end
      end

      # Placed this cycle by a parent still on the connection, or by none
      def placed?(child)
        return false unless @placed&.key?(child)

        placer = @placed[child]
        placer.nil? || components[placer.live_id].equal?(placer)
      end

      def placed_by(component)
        @placed ? @placed.filter_map { |child, placer| child if placer.equal?(component) } : []
      end

      def forget_refused(component)
        refused.delete(component.live_id) if refused[component.live_id].equal?(component)
      end

      # @return [Hash<String, LiveCable::Component>]
      def refused
        @refused ||= {}
      end

      # One that never subscribed runs no disconnect callbacks
      def leave(component)
        return component.disconnect if component.connected?

        remove_component(component)
        component.live_connection = nil
      end

      def cleanup_shared_container
        return if components.any?

        shared = containers.delete(Connection::SHARED_CONTAINER)
        shared&.cleanup
      end
    end
  end
end
