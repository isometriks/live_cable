# frozen_string_literal: true

module StreamBadgeHelper
  def stream_badge(message) = live('badge', id: message.id, label: message.body)
end
