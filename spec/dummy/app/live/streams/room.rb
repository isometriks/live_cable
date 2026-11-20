# frozen_string_literal: true

module Live
  module Streams
    class Room < LiveCable::Component
      reactive :heading, -> { 'Room' }
      reactive :topic, -> { 'general' }

      actions :retitle, :retopic

      def retitle(params) = self.heading = params[:heading]
      def retopic(params) = self.topic = params[:topic]
    end
  end
end
