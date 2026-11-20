# frozen_string_literal: true

module Live
  module Streams
    class Chat < LiveCable::Component
      reactive :room_name, -> { 'Lobby' }
      reactive :expanded, -> { true }
      reactive :density, -> { 'cozy' }
      reactive :draft, -> { '' }

      stream :messages, -> { ChatMessage.recent }
      stream :notices, -> { ChatMessage.notices }, dom_id: ->(notice) { "notice-#{notice.id}" }, limit: 3

      actions :toggle, :compact, :type, :add

      after_connect { stream_from('chat') { |id| stream_insert(:messages, ChatMessage.new(id:, body: 'streamed')) } }

      def toggle = self.expanded = !expanded
      def compact = self.density = 'compact'
      def type(params) = self.draft = params[:text]
      def add(params) = stream_insert(:messages, ChatMessage.new(id: params[:id].to_i, body: params[:body]))

      # Untracked, so changing it renders nothing
      def hidden? = @hidden

      def hide_quietly = @hidden = true
      def show_quietly = @hidden = false
    end
  end
end
