# frozen_string_literal: true

module LiveCable
  class Connection
    module ComponentManagement
      extend ActiveSupport::Concern

      def get_component(id)
        components[id]
      end

      def add_component(component)
        synchronize do
          component.live_connection = self
          components[component.live_id] = component
          @placed&.add(component)
        end
      end

      # Destroys the children a render no longer places. During a render cycle
      # that waits for its end, as another parent may place them again.
      #
      # @param children [Array<LiveCable::Component>]
      def drop(children)
        @dropped ? @dropped.merge(children) : destroy_dropped(children)
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
          @placed = Set.new.compare_by_identity
          yield
          destroy_dropped(@dropped, @placed)
        ensure
          @dropped = @placed = nil
        end
      end

      # Destroys them and takes them, with their children, off the connection,
      # so rendering their live ids again builds new components
      def destroy_dropped(children, placed = Set.new.compare_by_identity)
        children.each do |child|
          next if placed.include?(child) || !components[child.live_id].equal?(child)

          grandchildren = child.owned_children
          child.broadcast_destroy
          leave(child)
          destroy_dropped(grandchildren, placed)
        rescue StandardError => error
          # Reported, not raised: the render that dropped the child did nothing wrong
          Rails.error.report(error)
        end
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
