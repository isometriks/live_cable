# frozen_string_literal: true

module LiveCable
  class Component
    module Identification
      extend ActiveSupport::Concern

      included do
        attr_reader :id
      end

      class_methods do
        def component_string
          name.underscore.delete_prefix('live/')
        end

        def component_id(id)
          "#{component_string}/#{id}"
        end
      end

      def live_id
        self.class.component_id(id)
      end

      def channel_name
        "#{live_connection.channel_name}/#{live_id}"
      end
    end
  end
end
