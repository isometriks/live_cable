# frozen_string_literal: true

module Live
  module Streams
    class Paged < LiveCable::Component
      compound

      reactive :kind, -> { 'list' }

      stream :items, -> { ChatMessage.recent }

      actions :show

      def show(params) = self.kind = params[:kind]

      def variant = kind
    end
  end
end
