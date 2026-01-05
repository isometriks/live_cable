# frozen_string_literal: true

module LiveCable
  class Connection
    module ChannelManagement
      extend ActiveSupport::Concern

      def channel_name
        "live_#{session_id}"
      end
    end
  end
end
